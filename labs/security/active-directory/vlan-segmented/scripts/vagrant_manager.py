#!/usr/bin/env python3
"""
vagrant_manager.py

Interactive manager for the Pentest VLAN Lab.

Provides a Rich-based Python CLI while preserving the behavior
of the original Bash manager.

Features:
- VLAN-based inventory grouping
- OPNsense direct SSH
- Supports both KVM/libvirt and VirtualBox against the lab's unified
  Vagrantfile (select with --provider, or VAGRANT_DEFAULT_PROVIDER; see
  resolve_provider() for precedence)
- Sequential start of all VMs to preserve network boot order
- Interactive per-VM management
- Safe non-interactive destroy behavior
- LAB_PROFILE-aware: "Start All" / "Halt All" and the no-args CLI
  default only target VMs that actually exist under the Vagrantfile's
  current profile (explicit LAB_PROFILE, or its hardware-based
  auto-detection when LAB_PROFILE is unset), instead of always
  targeting all 12 known VMs.

Requires:
    rich

Install:
    pip install rich
"""

from __future__ import annotations

import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Confirm, Prompt
from rich.table import Table


console = Console()

# ========================== CONFIGURATION ==========================

VAGRANTFILE_CANDIDATES = ("Vagrantfile",)

SUPPORTED_PROVIDERS = ("libvirt", "virtualbox")


def resolve_provider(cli_provider: str | None) -> str:
    """
    Resolve which provider this run should target.

    Mirrors the Vagrantfile's own current_provider() precedence exactly,
    so the manager and the Vagrantfile always agree on which provider is
    active for a given invocation:

        1. --provider CLI flag (highest precedence)
        2. VAGRANT_DEFAULT_PROVIDER environment variable
        3. OS-based default: libvirt on Linux, virtualbox otherwise
    """
    if cli_provider:
        return cli_provider

    env_provider = os.environ.get("VAGRANT_DEFAULT_PROVIDER")

    if env_provider:
        return env_provider

    return "libvirt" if platform.system() == "Linux" else "virtualbox"


# Resolved once in main() via resolve_provider() and read by every
# run_vagrant() call afterward. Set to a safe default here so any code
# path that runs before main() (e.g. tests importing this module) still
# has a defined value rather than None.
SELECTED_PROVIDER: str = "libvirt"

# Explicit lab inventory.
#
# Keep the exact case-sensitive machine IDs used by the Vagrantfile.
#
# VLAN 10 intentionally appears first in ALL_VMS so the router/DC
# infrastructure boots before dependent clients.

VLAN_10 = ("opnsense", "DC01", "DB01", "CA01-ESC")
VLAN_20 = ("WIN10", "print01")
VLAN_30 = ("linux01", "llm01", "cloud-pentest")
VLAN_40 = ("metasploitable2", "juice-shop")
VLAN_99 = ("kali",)

# Known attacker-box presets offered by the "Attacker box" menu option.
# Anything else can still be typed in via the "custom" option.
ATTACKER_BOX_PRESETS = {
    "kali": (None, None),  # None clears the override -> Vagrantfile default
    "parrot": ("ParrotSec/Parrot-security-7.3-libvirt-amd64", "7.3"),
}

ALL_VMS = (
    *VLAN_10,
    *VLAN_20,
    *VLAN_30,
    *VLAN_40,
    *VLAN_99,
)

# UI rendering order: top to bottom.

VLAN_GROUPS = {
    "VLAN 99 - ATTACKER": VLAN_99,
    "VLAN 40 - DMZ / PUBLIC": VLAN_40,
    "VLAN 30 - LINUX SERVERS": VLAN_30,
    "VLAN 20 - WORKSTATIONS": VLAN_20,
    "VLAN 10 - AD CORE / ROUTER": VLAN_10,
}

STATE_ICONS = {
    "running": "[green]▶[/green]",
    "paused": "[yellow]⏸[/yellow]",
    "poweroff": "[red]■[/red]",
    "not_created": "[red]■[/red]",
    "default": "[bright_black]?[/bright_black]",
}

# Vagrant's machine-readable state values that we recognize.
KNOWN_STATES = {
    "running",
    "paused",
    "poweroff",
    "not_created",
    "aborted",
    "saved",
    "unknown",
    "stopping",
    "starting",
}


@dataclass(frozen=True)
class VmAction:
    """Result of a Vagrant operation."""

    name: str
    ok: bool
    detail: str = ""
    returncode: int | None = None


# ========================== VAGRANTFILE DISCOVERY ==========================


def find_vagrantfile() -> Path | None:
    """Find a Vagrantfile in the current directory or any parent."""
    here = Path.cwd()

    for directory in (here, *here.parents):
        for name in VAGRANTFILE_CANDIDATES:
            vagrantfile = directory / name

            if vagrantfile.is_file():
                return vagrantfile

    return None


# ========================== VAGRANT INVENTORY ==========================


def get_vagrant_inventory(
    vagrantfile: Path,
) -> tuple[dict[str, str], dict[str, str]]:
    """
    Collect VM states and SSH endpoints.

    Uses Vagrant's machine-readable status output for reliable state
    detection and a single `vagrant ssh-config` call for running VMs.
    """
    states: dict[str, str] = {}
    ssh_hosts: dict[str, str] = {}

    if not shutil.which("vagrant"):
        return states, ssh_hosts

    # ------------------------------------------------------------------
    # 1. Get machine states.
    # ------------------------------------------------------------------

    try:
        result = subprocess.run(
            [
                "vagrant",
                "status",
                "--machine-readable",
            ],
            cwd=vagrantfile.parent,
            capture_output=True,
            text=True,
            check=False,
            stdin=subprocess.DEVNULL,
        )
    except (FileNotFoundError, OSError):
        return states, ssh_hosts

    if result.returncode == 0:
        for line in result.stdout.splitlines():
            parts = line.split(",")

            if len(parts) < 4:
                continue

            if parts[2] != "state":
                continue

            vm_name = parts[1].strip()
            state = parts[3].strip()

            if vm_name and state:
                states[vm_name] = state

    # ------------------------------------------------------------------
    # 2. Get SSH endpoints only for running machines.
    # ------------------------------------------------------------------

    running_vms = [
        vm
        for vm, state in states.items()
        if state == "running"
    ]

    if not running_vms:
        return states, ssh_hosts

    try:
        result = subprocess.run(
            ["vagrant", "ssh-config", *running_vms],
            cwd=vagrantfile.parent,
            capture_output=True,
            text=True,
            check=False,
            stdin=subprocess.DEVNULL,
        )
    except (FileNotFoundError, OSError):
        return states, ssh_hosts

    if result.returncode != 0:
        return states, ssh_hosts

    current_vm: str | None = None

    for line in result.stdout.splitlines():
        stripped = line.strip()

        if stripped.startswith("Host "):
            parts = stripped.split(maxsplit=1)

            if len(parts) == 2:
                current_vm = parts[1].strip()

        elif stripped.startswith("HostName ") and current_vm:
            parts = stripped.split(maxsplit=1)

            if len(parts) == 2:
                ssh_hosts[current_vm] = parts[1].strip()
                current_vm = None

    return states, ssh_hosts


# ========================== VAGRANT EXECUTION ==========================


def resolve_active_vms(
    vagrantfile: Path,
) -> tuple[list[str], bool]:
    """
    Determine which known lab VMs actually exist under the Vagrantfile's
    current LAB_PROFILE.

    Uses `vagrant status --machine-readable` (via get_vagrant_inventory)
    as the source of truth rather than re-implementing the Vagrantfile's
    PROFILES table or its hardware-based get_optimal_profile auto-detect
    logic in Python. `vagrant status` already reflects whichever profile
    the Vagrantfile resolved to -- explicit LAB_PROFILE or auto-detected
    -- because it lists exactly the machines the current run's
    `config.vm.define` calls actually produced.

    Returns (active_vm_names_in_declared_order, resolved_via_status).
    If `vagrant status` is unavailable or returns nothing, falls back to
    the full ALL_VMS inventory and reports resolved_via_status=False, so
    callers can fall back to the previous unconditional behavior.
    """
    states, _ = get_vagrant_inventory(vagrantfile)

    if not states:
        return list(ALL_VMS), False

    active = [vm for vm in ALL_VMS if vm in states]
    return (active or list(ALL_VMS)), True


def parse_profiles(vagrantfile: Path) -> dict[str, dict] | None:
    """
    Parse the Vagrantfile's PROFILES hash, e.g.:

        PROFILES = {
          'ad' => {
            description: '...',
            vms: %w[opnsense DC01 kali WIN10 CA01-ESC DB01 linux01],
            min_ram: 16384,
            recommended_ram: 32768
          },
          ...
        }

    Returns None if no PROFILES block is found (older Vagrantfile, or
    a lab without profile support).
    """
    try:
        text = vagrantfile.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None

    block = re.search(r"PROFILES\s*=\s*\{(.*?)\n\}\n", text, re.S)

    if not block:
        return None

    profiles: dict[str, dict] = {}

    for entry in re.finditer(
        r"""['"](?P<name>[\w-]+)['"]\s*=>\s*\{(?P<body>.*?)\},?\s*"""
        r"""(?=\n\s*['"][\w-]+['"]\s*=>\s*\{|\Z)""",
        block.group(1),
        re.S,
    ):
        name = entry.group("name")
        body = entry.group("body")
        vms_match = re.search(r"vms:\s*%w\[([^\]]*)\]", body)
        ram_match = re.search(r"min_ram:\s*(\d+)", body)
        rec_match = re.search(r"recommended_ram:\s*(\d+)", body)

        profiles[name] = {
            "vms": vms_match.group(1).split() if vms_match else [],
            "min_ram": int(ram_match.group(1)) if ram_match else None,
            "recommended_ram": (
                int(rec_match.group(1)) if rec_match else None
            ),
        }

    return profiles or None


def best_override_profile(vagrantfile: Path, vm: str) -> tuple[str, dict] | None:
    """
    Pick the most-scoped profile that includes `vm`, preferring a
    narrower named profile over 'full' when a VM belongs to both.

    Returns (profile_name, profile_info) or None if the Vagrantfile
    has no PROFILES block or no profile includes this VM.
    """
    profiles = parse_profiles(vagrantfile)

    if not profiles:
        return None

    hits = sorted(
        name for name, info in profiles.items() if vm in info["vms"]
    )

    if not hits:
        return None

    narrower = [name for name in hits if name != "full"]
    chosen = narrower[0] if narrower else hits[0]
    return chosen, profiles[chosen]


def require_vagrant() -> bool:
    """Return True when Vagrant is available on PATH."""
    if shutil.which("vagrant"):
        return True

    console.print(
        "[bold red]Error:[/bold red] 'vagrant' was not found on PATH. "
        "Install Vagrant or activate the environment that provides it."
    )

    return False


def build_vagrant_environment() -> dict[str, str]:
    """Build the environment used for every Vagrant invocation."""
    env = os.environ.copy()
    env["VAGRANT_DEFAULT_PROVIDER"] = SELECTED_PROVIDER
    return env


def run_vagrant(
    action: str,
    vagrantfile: Path,
    vm: str | None = None,
    vms_list: list[str] | tuple[str, ...] | None = None,
    extra_args: list[str] | None = None,
    profile_override: str | None = None,
) -> VmAction:
    """
    Run a Vagrant subcommand from the Vagrantfile directory.

    Uses the provider resolved into SELECTED_PROVIDER (see
    resolve_provider()). For "up" and "reload" -- the only actions where
    provider selection actually matters, since other actions operate on
    an already-created machine tied to whichever provider created it --
    an explicit --provider flag is passed on the command line. This
    matches Vagrant's own precedence (CLI flag beats
    VAGRANT_DEFAULT_PROVIDER) and mirrors the Vagrantfile's own
    current_provider() detection, so the two always agree.

    SSH receives the normal interactive stdin. Other commands receive
    /dev/null so unexpected prompts cannot block the manager.

    profile_override, if given, sets LAB_PROFILE for this subprocess
    only (see build_vagrant_environment) -- it does not change the
    manager's own os.environ, so the rest of the session is unaffected.
    """
    cmd = ["vagrant", action]

    if action in ("up", "reload"):
        cmd.extend(["--provider", SELECTED_PROVIDER])

    if vms_list:
        cmd.extend(vms_list)
    elif vm:
        cmd.append(vm)

    if extra_args:
        cmd.extend(extra_args)

    label = (
        ", ".join(vms_list)
        if vms_list
        else (vm or "(all)")
    )

    env = build_vagrant_environment()

    if profile_override:
        env["LAB_PROFILE"] = profile_override
        console.print(
            f"[dim]Running this action with LAB_PROFILE="
            f"{profile_override} (this session stays on its own "
            f"profile otherwise).[/dim]"
        )

    console.rule(
        f"[bold cyan]vagrant {action}[/bold cyan] {label}"
    )

    stdin_arg = (
        None
        if action == "ssh"
        else subprocess.DEVNULL
    )

    try:
        result = subprocess.run(
            cmd,
            cwd=vagrantfile.parent,
            env=env,
            stdin=stdin_arg,
            check=False,
        )
    except FileNotFoundError:
        return VmAction(
            name=label,
            ok=False,
            detail="vagrant not found",
        )
    except OSError as exc:
        return VmAction(
            name=label,
            ok=False,
            detail=str(exc),
        )
    except KeyboardInterrupt:
        console.print(
            "[yellow]Interrupted by user.[/yellow]"
        )

        return VmAction(
            name=label,
            ok=False,
            detail="interrupted",
        )

    if result.returncode == 0:
        return VmAction(
            name=label,
            ok=True,
            returncode=result.returncode,
        )

    return VmAction(
        name=label,
        ok=False,
        detail=f"exit code {result.returncode}",
        returncode=result.returncode,
    )


def switch_attacker_box() -> None:
    """
    Interactively change the KALI_BOX / KALI_BOX_VERSION override used
    for the "kali" VM on the next vagrant subprocess this session makes
    (see build_vagrant_environment()). Does not touch an already-running
    VM -- that needs a destroy + up to pick up the new box.
    """
    current_box = os.environ.get("KALI_BOX", "kalilinux/rolling")
    current_version = os.environ.get("KALI_BOX_VERSION", "2026.1.0")
    console.print(
        Panel.fit(
            "[bold]Attacker box (kali VM)[/bold]\n"
            f"Current: [cyan]{current_box}[/cyan] @ {current_version}",
            border_style="cyan",
        )
    )
    box_choice = Prompt.ask(
        "Choose an attacker box",
        choices=["kali", "parrot", "custom", "cancel"],
        default="cancel",
    )

    if box_choice == "cancel":
        return

    if box_choice in ATTACKER_BOX_PRESETS:
        box, version = ATTACKER_BOX_PRESETS[box_choice]
        if box is None:
            os.environ.pop("KALI_BOX", None)
            os.environ.pop("KALI_BOX_VERSION", None)
            console.print(
                "[green]Attacker box reset to the Kali default "
                "(kalilinux/rolling).[/green]"
            )
        else:
            os.environ["KALI_BOX"] = box
            os.environ["KALI_BOX_VERSION"] = version
            console.print(
                f"[green]Attacker box set to {box} @ {version}.[/green]\n"
                "[yellow]Unverified against this repo's Kali-specific "
                "guides -- confirm the box/version exists on Vagrant "
                "Cloud for your provider before relying on it.[/yellow]"
            )
    else:  # custom
        custom_box = Prompt.ask(
            "Box (org/name)",
            default=os.environ.get("KALI_BOX", ""),
        )
        if not custom_box:
            console.print(
                "[yellow]No box entered -- leaving the current setting "
                "unchanged.[/yellow]"
            )
            return

        custom_version = Prompt.ask(
            "Box version (blank = latest)",
            default=os.environ.get("KALI_BOX_VERSION", ""),
        )
        os.environ["KALI_BOX"] = custom_box
        if custom_version:
            os.environ["KALI_BOX_VERSION"] = custom_version
        else:
            os.environ.pop("KALI_BOX_VERSION", None)

        console.print(
            f"[green]Attacker box set to {custom_box}"
            + (f" @ {custom_version}" if custom_version else "")
            + ".[/green]"
        )

    console.print(
        "[dim]Takes effect on the next 'up'/'reload' for kali -- an "
        "already-running kali VM keeps its current box until it's "
        "destroyed and brought up again.[/dim]"
    )
    Prompt.ask(
        "[bright_black]Press Enter to continue...[/bright_black]",
        default="",
    )


def ssh_opnsense(host: str) -> VmAction:
    """
    Connect directly to OPNsense using root SSH.

    This intentionally bypasses `vagrant ssh` because OPNsense requires
    direct root-shell access.
    """
    console.print(
        "[yellow]Attempting direct SSH to OPNsense...[/yellow]"
    )

    if not host or host == "N/A":
        console.print(
            "[red]Could not determine OPNsense SSH host "
            "for direct connection.[/red]"
        )

        return VmAction(
            name="opnsense",
            ok=False,
            detail="missing host",
        )

    if not shutil.which("ssh"):
        return VmAction(
            name="opnsense",
            ok=False,
            detail="ssh not found",
        )

    try:
        result = subprocess.run(
            ["ssh", f"root@{host}"],
            check=False,
        )
    except FileNotFoundError:
        return VmAction(
            name="opnsense",
            ok=False,
            detail="ssh not found",
        )
    except OSError as exc:
        return VmAction(
            name="opnsense",
            ok=False,
            detail=str(exc),
        )
    except KeyboardInterrupt:
        return VmAction(
            name="opnsense",
            ok=False,
            detail="interrupted",
        )

    if result.returncode == 0:
        return VmAction(
            name="opnsense",
            ok=True,
            returncode=result.returncode,
        )

    return VmAction(
        name="opnsense",
        ok=False,
        detail=f"exit code {result.returncode}",
        returncode=result.returncode,
    )


# ========================== UI ==========================


def show_main_menu(
    states: dict[str, str],
    ssh_hosts: dict[str, str],
    status_resolved: bool,
) -> tuple[dict[str, str], dict[str, str]]:
    """
    Render the main menu.

    When status_resolved is True, a VM name absent from `states` is not
    just "not created" -- it isn't defined at all under the current
    LAB_PROFILE, and is shown as excluded rather than startable.

    Excluded VMs are listed for discoverability but are intentionally
    left out of the returned `options` mapping: they don't exist under
    the Vagrantfile's current LAB_PROFILE, so passing one to `vagrant`
    fails with "was not found configured for this Vagrant environment"
    instead of a clean, actionable message. Callers should route their
    selection number through `excluded` first.

    Returns (options, excluded):
        options:  selection number -> VM name, for VMs that are
                  selectable right now.
        excluded: selection number -> VM name, for VMs excluded by the
                  current LAB_PROFILE. Callers can use the name to look
                  up which profile would include it (see
                  best_override_profile) and offer an assisted switch.
    """
    console.clear()

    box_line = (
        f"\n[dim]Attacker box: {os.environ['KALI_BOX']}[/dim]"
        if os.environ.get("KALI_BOX")
        else ""
    )
    console.print(
        Panel.fit(
            "[bold white]PENTEST VLAN LAB MANAGER v4.1[/bold white]\n"
            f"[dim]Provider: {SELECTED_PROVIDER}[/dim]{box_line}",
            border_style="blue",
        )
    )

    if status_resolved:
        active_count = sum(1 for vm in ALL_VMS if vm in states)
        console.print(
            f"[dim]LAB_PROFILE: {active_count} of {len(ALL_VMS)} known "
            f"VMs active -- set LAB_PROFILE to change "
            f"(see the Vagrantfile's PROFILES table)[/dim]"
        )

    table = Table(
        show_header=False,
        box=None,
        padding=(0, 1, 0, 1),
    )

    table.add_column("ID", style="cyan", width=5)
    table.add_column("VM", style="white", width=18)
    table.add_column("State", width=15)
    table.add_column(
        "IP/Host",
        style="bright_black",
    )

    index = 1
    options: dict[str, str] = {}
    excluded: dict[str, str] = {}

    for vlan_name, configured_vms in VLAN_GROUPS.items():
        table.add_row(
            "",
            f"[bold purple]{vlan_name}[/bold purple]",
            "",
            "",
            style="underline",
        )

        for vm in configured_vms:
            if status_resolved and vm not in states:
                table.add_row(
                    f"[{index:02d}]",
                    f"[dim]{vm}[/dim]",
                    "[yellow]excluded (LAB_PROFILE)[/yellow]",
                    "",
                )
                excluded[str(index)] = vm
                index += 1
                continue

            state = states.get(
                vm,
                "not_created",
            )

            icon = STATE_ICONS.get(
                state,
                STATE_ICONS["default"],
            )

            host = ssh_hosts.get(
                vm,
                "N/A",
            )

            table.add_row(
                f"[{index:02d}]",
                vm,
                f"{icon} {state}",
                host,
            )

            options[str(index)] = vm
            index += 1

        table.add_row()

    console.print(table)

    console.print(
        "[cyan][A] Start All   "
        "[B] Halt All   "
        "[K] Attacker box   "
        "[R] Refresh   "
        "[Q] Quit[/cyan]"
    )

    return options, excluded


def vm_menu(
    vagrantfile: Path,
    vm: str,
    profile_override: str | None = None,
) -> None:
    """
    Display the individual VM management menu.

    profile_override, if set, means this VM was reached via the
    assisted profile-switch (the VM isn't in the current session's
    LAB_PROFILE) and is applied to every action run from this menu,
    scoped to each subprocess call only.
    """
    while True:
        states, ssh_hosts = get_vagrant_inventory(
            vagrantfile
        )

        state = states.get(
            vm,
            "not_created",
        )

        host = ssh_hosts.get(
            vm,
            "N/A",
        )

        console.clear()

        detail_box_line = (
            f"\n[dim]Attacker box: {os.environ['KALI_BOX']}[/dim]"
            if os.environ.get("KALI_BOX")
            else ""
        )
        console.print(
            Panel.fit(
                "[bold white]"
                "PENTEST VLAN LAB MANAGER v4.1"
                "[/bold white]\n"
                f"[dim]Provider: {SELECTED_PROVIDER}[/dim]{detail_box_line}",
                border_style="blue",
            )
        )

        console.print(
            f"VM:    [cyan]{vm}[/cyan]"
        )
        console.print(
            f"State: {state}"
        )
        console.print(
            f"Host:  {host}"
        )

        if profile_override:
            console.print(
                f"[yellow]Note: actions here run with "
                f"LAB_PROFILE={profile_override} "
                f"(outside this session's profile).[/yellow]"
            )

        console.print("\n[cyan][S] SSH[/cyan]")
        console.print("[cyan][U] Up[/cyan]")
        console.print("[cyan][H] Halt[/cyan]")
        console.print("[cyan][D] Destroy[/cyan]")
        console.print("[cyan][R] Reload[/cyan]")
        console.print("[cyan][B] Back[/cyan]")

        choice = Prompt.ask(
            "[bold]Action[/bold]",
            default="B",
        ).upper()

        if choice == "S":
            if state != "running":
                console.print(
                    f"[yellow]{vm} is not running. "
                    "Start it before connecting via SSH."
                    "[/yellow]"
                )

            elif vm == "opnsense":
                result = ssh_opnsense(host)

                if not result.ok:
                    console.print(
                        f"[red]OPNsense SSH failed: "
                        f"{result.detail}[/red]"
                    )

            else:
                run_vagrant(
                    "ssh",
                    vagrantfile,
                    vm=vm,
                    profile_override=profile_override,
                )

        elif choice == "U":
            run_vagrant(
                "up",
                vagrantfile,
                vm=vm,
                profile_override=profile_override,
            )

        elif choice == "H":
            run_vagrant(
                "halt",
                vagrantfile,
                vm=vm,
                profile_override=profile_override,
            )

        elif choice == "D":
            if Confirm.ask(
                f"[bold red]Really destroy {vm}?"
                "[/bold red]",
                default=False,
            ):
                run_vagrant(
                    "destroy",
                    vagrantfile,
                    vm=vm,
                    extra_args=["-f"],
                    profile_override=profile_override,
                )

        elif choice == "R":
            run_vagrant(
                "reload",
                vagrantfile,
                vm=vm,
                profile_override=profile_override,
            )

        elif choice == "B":
            return

        else:
            console.print(
                "[red]Invalid option[/red]"
            )

        Prompt.ask(
            "[bright_black]Press Enter to continue...[/bright_black]",
            default="",
        )


# ========================== GROUP ACTIONS ==========================


def start_all(
    vagrantfile: Path,
    vms: tuple[str, ...] | list[str],
) -> VmAction:
    """
    Start the given lab VMs sequentially.

    --no-parallel is intentional and preserves the original Bash
    manager's network boot ordering. Callers should pass the VMs
    active under the current LAB_PROFILE (see resolve_active_vms),
    not unconditionally ALL_VMS.
    """
    console.print(
        "[green]Starting all VMs...[/green]"
    )

    return run_vagrant(
        "up",
        vagrantfile,
        vms_list=vms,
        extra_args=["--no-parallel"],
    )


def halt_all(
    vagrantfile: Path,
    vms: tuple[str, ...] | list[str],
) -> VmAction:
    """Halt the given lab VMs."""
    console.print(
        "[yellow]Halting all VMs...[/yellow]"
    )

    return run_vagrant(
        "halt",
        vagrantfile,
        vms_list=vms,
    )


# ========================== CLI HELPERS ==========================


def validate_vm_names(
    requested: list[str],
    states: dict[str, str],
) -> list[str]:
    """
    Validate explicitly supplied VM names.

    Uses Vagrant's discovered inventory when available and falls back
    to the authoritative ALL_VMS inventory when status is unavailable.
    """
    if not requested:
        return []

    known = set(states) if states else set(ALL_VMS)

    unknown = [
        vm
        for vm in requested
        if vm not in known
    ]

    if unknown:
        console.print(
            "[bold red]Unknown VM(s):[/bold red] "
            + ", ".join(unknown)
        )

        console.print(
            "[dim]Known lab VMs:[/dim] "
            + ", ".join(ALL_VMS)
        )

        return []

    # Preserve order while removing duplicates.
    return list(dict.fromkeys(requested))


def print_results(
    results: list[VmAction],
) -> None:
    """Display operation results."""
    table = Table(
        title="Result",
        show_lines=False,
    )

    table.add_column("Target")
    table.add_column("Status")
    table.add_column("Detail")

    for result in results:
        status = (
            "[green]OK[/green]"
            if result.ok
            else "[red]FAILED[/red]"
        )

        table.add_row(
            result.name,
            status,
            result.detail,
        )

    console.print(table)


# ========================== MAIN ==========================


def main() -> int:
    """Program entry point."""
    parser = argparse.ArgumentParser(
        description="Manage Pentest Lab VLAN VMs."
    )

    parser.add_argument(
        "action",
        nargs="?",
        choices=[
            "up",
            "halt",
            "reload",
            "provision",
            "destroy",
            "status",
        ],
        help=(
            "Action: up (start), halt (stop), reload (restart), "
            "provision (run provisioning), destroy (delete), "
            "status (show)."
        ),
    )

    parser.add_argument(
        "vms",
        nargs="*",
        help="VM names to target (default: all).",
    )

    parser.add_argument(
        "--provision",
        action="store_true",
        help=(
            "Run Vagrant provisioning with the "
            "'up' or 'reload' action."
        ),
    )

    parser.add_argument(
        "--provider",
        choices=SUPPORTED_PROVIDERS,
        default=None,
        help=(
            "Provider to use (libvirt or virtualbox). Defaults to "
            "VAGRANT_DEFAULT_PROVIDER if set, otherwise libvirt on "
            "Linux and virtualbox elsewhere -- matching the "
            "Vagrantfile's own default."
        ),
    )

    parser.add_argument(
        "--kali-box",
        default=None,
        metavar="ORG/NAME",
        help=(
            "Override the attacker VM's box for this run (sets "
            "KALI_BOX for the vagrant subprocess), e.g. --kali-box "
            "ParrotSec/Parrot-security-7.3-libvirt-amd64 to use Parrot "
            "Security instead of Kali Linux. The VM keeps the name "
            "'kali' either way. Combine with --kali-box-version."
        ),
    )

    parser.add_argument(
        "--kali-box-version",
        default=None,
        metavar="VERSION",
        help="Box version to pair with --kali-box, e.g. 7.3.",
    )

    args = parser.parse_args()

    global SELECTED_PROVIDER
    SELECTED_PROVIDER = resolve_provider(args.provider)

    # Applied to this process's environment so every vagrant subprocess
    # this run makes (interactive or one-shot) inherits it via
    # build_vagrant_environment()'s os.environ.copy().
    if args.kali_box:
        os.environ["KALI_BOX"] = args.kali_box
    if args.kali_box_version:
        os.environ["KALI_BOX_VERSION"] = args.kali_box_version

    # ------------------------------------------------------------------
    # Find Vagrantfile.
    # ------------------------------------------------------------------

    vagrantfile = find_vagrantfile()

    if vagrantfile is None:
        console.print(
            "[bold red]Error:[/bold red] No Vagrantfile found "
            "in this directory or any parent."
        )
        return 1

    # ------------------------------------------------------------------
    # Require Vagrant.
    # ------------------------------------------------------------------

    if not require_vagrant():
        return 1

    console.print(
        f"[dim]Provider: [bold]{SELECTED_PROVIDER}[/bold] "
        "(override with --provider or VAGRANT_DEFAULT_PROVIDER)[/dim]"
    )
    if os.environ.get("KALI_BOX"):
        box_version = os.environ.get("KALI_BOX_VERSION")
        console.print(
            f"[dim]Attacker box (kali): [bold]{os.environ['KALI_BOX']}[/bold]"
            + (f" @ {box_version}" if box_version else "")
            + " (override with --kali-box/--kali-box-version or "
            "KALI_BOX/KALI_BOX_VERSION)[/dim]"
        )

    # ------------------------------------------------------------------
    # Non-interactive CLI mode.
    # ------------------------------------------------------------------

    if args.action:
        if args.action == "status":
            result = run_vagrant(
                "status",
                vagrantfile,
            )

            return 0 if result.ok else 1

        states, _ = get_vagrant_inventory(
            vagrantfile
        )

        targets = validate_vm_names(
            args.vms,
            states,
        )

        if args.vms and not targets:
            return 1

        # Safety: never allow an implicit global destroy.
        if (
            args.action == "destroy"
            and not args.vms
        ):
            console.print(
                "[bold red]Error:[/bold red] Refusing to "
                "destroy all VMs without explicit targets."
            )

            console.print(
                "Specify VMs to destroy, for example:"
            )

            console.print(
                "  python3 vagrant_manager.py "
                "destroy kali DC01"
            )

            return 1

        # Determine additional Vagrant arguments.
        if args.action == "destroy":
            extra = ["-f"]

        elif (
            args.action in {"up", "reload"}
            and args.provision
        ):
            extra = ["--provision"]

        else:
            extra = None

        results: list[VmAction] = []

        # ------------------------------------------------------------------
        # No explicit VM targets.
        #
        # Preserve lab-wide policies:
        #   up       -> active-profile VMs + --no-parallel
        #   halt     -> active-profile VMs
        #   reload   -> active-profile VMs
        #   provision -> active-profile VMs
        #
        # "Active-profile VMs" comes from `vagrant status`, which already
        # reflects the Vagrantfile's LAB_PROFILE (explicit or
        # auto-detected) -- not a hardcoded ALL_VMS list. If `vagrant
        # status` is unavailable, this falls back to ALL_VMS, matching
        # the previous unconditional behavior.
        # ------------------------------------------------------------------

        if not args.vms:
            active_vms, status_resolved = resolve_active_vms(
                vagrantfile
            )

            if status_resolved and len(active_vms) < len(ALL_VMS):
                console.print(
                    f"[dim]LAB_PROFILE resolved to {len(active_vms)} "
                    f"of {len(ALL_VMS)} known VMs: "
                    f"{', '.join(active_vms)}[/dim]"
                )

            if args.action == "up":
                results.append(
                    run_vagrant(
                        "up",
                        vagrantfile,
                        vms_list=active_vms,
                        extra_args=["--no-parallel"],
                    )
                )

            elif args.action in {
                "halt",
                "reload",
                "provision",
            }:
                results.append(
                    run_vagrant(
                        args.action,
                        vagrantfile,
                        vms_list=active_vms,
                        extra_args=extra,
                    )
                )

        # ------------------------------------------------------------------
        # Explicit VM targets.
        # ------------------------------------------------------------------

        else:
            for vm in targets:
                results.append(
                    run_vagrant(
                        args.action,
                        vagrantfile,
                        vm=vm,
                        extra_args=extra,
                    )
                )

        if results:
            print_results(results)

            if any(
                not result.ok
                for result in results
            ):
                return 1

        return 0

    # ------------------------------------------------------------------
    # Interactive mode.
    # ------------------------------------------------------------------

    while True:
        states, ssh_hosts = get_vagrant_inventory(
            vagrantfile
        )
        active_vms = [vm for vm in ALL_VMS if vm in states] or list(ALL_VMS)
        status_resolved = bool(states)

        options, excluded = show_main_menu(
            states,
            ssh_hosts,
            status_resolved,
        )

        choice = Prompt.ask(
            "[bold]Selection[/bold]",
            default="R",
        )

        if choice.isdigit():
            if choice in options:
                vm_menu(
                    vagrantfile,
                    options[choice],
                )
                continue

            if choice in excluded:
                vm = excluded[choice]
                found = best_override_profile(vagrantfile, vm)

                if found is None:
                    console.print(
                        f"[yellow]'{vm}' isn't assigned to any "
                        f"profile in this Vagrantfile -- "
                        f"skipping.[/yellow]"
                    )
                elif Confirm.ask(
                    f"'{vm}' requires LAB_PROFILE={found[0]} "
                    f"({found[1]['description']}, "
                    f"recommended {found[1]['recommended_ram'] // 1024}GB "
                    f"RAM). This session is on a different profile. "
                    f"Run this one VM's actions under "
                    f"LAB_PROFILE={found[0]}?",
                    default=False,
                ):
                    vm_menu(
                        vagrantfile,
                        vm,
                        profile_override=found[0],
                    )
                else:
                    console.print("[yellow]Cancelled.[/yellow]")

                Prompt.ask(
                    "[bright_black]Press Enter to continue...[/bright_black]",
                    default="",
                )
                continue

        choice = choice.upper()

        if choice == "A":
            result = start_all(vagrantfile, active_vms)
            print_results([result])

        elif choice == "B":
            result = halt_all(vagrantfile, active_vms)
            print_results([result])

        elif choice == "K":
            switch_attacker_box()
            continue

        elif choice == "R":
            continue

        elif choice == "Q":
            console.print("Bye.")
            return 0

        else:
            console.print(
                "[red]Invalid option[/red]"
            )

            Prompt.ask(
                "[bright_black]Press Enter to continue...[/bright_black]",
                default="",
            )


if __name__ == "__main__":
    sys.exit(main())
