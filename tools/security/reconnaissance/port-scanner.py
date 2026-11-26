#!/usr/bin/env python3
"""
Modern Async Port Scanner

A lightweight reconnaissance tool for authorized security testing.

Features:
- TCP connect scanning
- Async concurrent scanning
- Banner grabbing
- Service identification
- JSON output
- CLI support

Note: --syn and --udp are accepted on the CLI but not yet implemented;
the scanner currently falls back to TCP connect scanning for both and
says so at runtime.

Author: solo2121
Version: 2.1
License: MIT
"""

from __future__ import annotations

import argparse
import asyncio
import json
import time
from dataclasses import asdict, dataclass
from enum import Enum
from pathlib import Path
from typing import Optional


class ScanType(Enum):
    """Supported scan types."""

    TCP_CONNECT = "tcp"
    TCP_SYN = "syn"
    UDP = "udp"


@dataclass(frozen=True)
class ScanResult:
    """Result returned from a port scan."""

    port: int
    is_open: bool
    scan_type: ScanType
    response_time: float = 0.0
    error: Optional[str] = None
    banner: Optional[str] = None
    target: str = ""


COMMON_SERVICES = {
    21: "ftp",
    22: "ssh",
    23: "telnet",
    25: "smtp",
    53: "dns",
    80: "http",
    110: "pop3",
    143: "imap",
    443: "https",
    445: "smb",
    3306: "mysql",
    3389: "rdp",
    5432: "postgresql",
    6379: "redis",
    8080: "http-alt",
}


def service_name(port: int) -> str:
    """Return common service name."""

    return COMMON_SERVICES.get(
        port,
        "unknown",
    )


def parse_ports(value: str) -> list[int]:
    """Parse port input."""

    ports: list[int] = []

    for item in value.split(","):

        item = item.strip()

        if "-" in item:

            start, end = item.split("-", 1)

            ports.extend(
                range(
                    int(start),
                    int(end) + 1,
                )
            )

        else:

            ports.append(int(item))

    return sorted(set(ports))


async def grab_banner(
    reader: asyncio.StreamReader,
    timeout: float,
) -> Optional[str]:
    """Attempt banner grabbing."""

    try:

        data = await asyncio.wait_for(
            reader.read(128),
            timeout=timeout,
        )

        if data:

            return data.decode(errors="ignore").strip()

    except (
        asyncio.TimeoutError,
        ConnectionResetError,
    ):
        pass

    return None


async def scan_port(
    target: str,
    port: int,
    timeout: float = 1.0,
    scan_type: ScanType = ScanType.TCP_CONNECT,
) -> ScanResult:
    """Scan a single port."""

    start = time.perf_counter()

    try:

        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(
                target,
                port,
            ),
            timeout=timeout,
        )

        banner = await grab_banner(
            reader,
            timeout,
        )

        writer.close()

        try:
            await writer.wait_closed()
        except Exception:
            pass

        return ScanResult(
            port=port,
            is_open=True,
            scan_type=scan_type,
            response_time=time.perf_counter() - start,
            banner=banner,
            target=target,
        )

    except ConnectionRefusedError:

        return ScanResult(
            port=port,
            is_open=False,
            scan_type=scan_type,
            response_time=time.perf_counter() - start,
            target=target,
        )

    except asyncio.TimeoutError:

        return ScanResult(
            port=port,
            is_open=False,
            scan_type=scan_type,
            response_time=time.perf_counter() - start,
            error="timeout",
            target=target,
        )

    except OSError as exc:

        return ScanResult(
            port=port,
            is_open=False,
            scan_type=scan_type,
            response_time=time.perf_counter() - start,
            error=str(exc),
            target=target,
        )


async def scan_ports(
    target: str,
    ports: list[int],
    timeout: float = 1.0,
    workers: int = 100,
    scan_type: ScanType = ScanType.TCP_CONNECT,
) -> list[ScanResult]:
    """Scan ports concurrently."""

    semaphore = asyncio.Semaphore(workers)

    async def limited_scan(port: int):

        async with semaphore:

            return await scan_port(
                target,
                port,
                timeout,
                scan_type,
            )

    return await asyncio.gather(*[limited_scan(port) for port in ports])


def display_results(
    results: list[ScanResult],
) -> None:
    """Display scan results."""

    print()

    print(f"{'PORT':<8}" f"{'STATE':<12}" "SERVICE")

    print("-" * 35)

    for result in sorted(
        results,
        key=lambda x: x.port,
    ):

        if result.is_open:

            print(f"{result.port:<8}" f"OPEN{'':<7}" f"{service_name(result.port)}")


async def async_main(args) -> None:
    """Application workflow."""

    if not args.target:

        print("No target supplied.")

        return

    if args.scan_type != ScanType.TCP_CONNECT:

        print(
            f"[!] {args.scan_type.value.upper()} scanning is not yet "
            "implemented; falling back to TCP connect scanning."
        )

        args.scan_type = ScanType.TCP_CONNECT

    ports = parse_ports(args.ports or "1-1024")

    print(f"[+] Scanning {args.target}")

    start = time.perf_counter()

    results = await scan_ports(
        target=args.target,
        ports=ports,
        timeout=args.timeout,
        workers=args.workers,
        scan_type=args.scan_type,
    )

    duration = time.perf_counter() - start

    display_results(results)

    print(f"\nCompleted in {duration:.2f}s")

    if args.output:

        output = [
            {
                **asdict(result),
                "scan_type": result.scan_type.value,
            }
            for result in results
        ]

        Path(args.output).write_text(
            json.dumps(
                output,
                indent=4,
            )
        )


def parse_args():
    """CLI argument parser."""

    parser = argparse.ArgumentParser(description="Modern Async Port Scanner")

    parser.add_argument(
        "target",
        nargs="?",
        default=None,
        help="Target IP or hostname",
    )

    parser.add_argument(
        "-p",
        "--ports",
        default=None,
        help="Ports: 22,80,443 or 1-1024",
    )

    parser.add_argument(
        "--timeout",
        type=float,
        default=1.0,
    )

    parser.add_argument(
        "--workers",
        type=int,
        default=100,
    )

    parser.add_argument(
        "-o",
        "--output",
    )

    scan_group = parser.add_mutually_exclusive_group()

    scan_group.add_argument(
        "--syn",
        action="store_const",
        const=ScanType.TCP_SYN,
        dest="scan_type",
    )

    scan_group.add_argument(
        "--udp",
        action="store_const",
        const=ScanType.UDP,
        dest="scan_type",
    )

    parser.set_defaults(scan_type=ScanType.TCP_CONNECT)

    return parser.parse_args()


def main():

    args = parse_args()

    asyncio.run(async_main(args))


if __name__ == "__main__":
    main()
