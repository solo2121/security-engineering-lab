#!/usr/bin/env python3
"""
vagrant_manager.py

Interactive manager for the lab's Vagrant VMs.

Provides an interactive Rich-based TUI while preserving the same
Vagrant operations as the original Bash manager.

VM discovery is LAB_PROFILE-aware: it parses the Vagrantfile's LAB_PROFILES
hash and reads the LAB_PROFILE environment variable (same default, "ad", as
the Vagrantfile itself), so "all" and the default target list only include
VMs that actually exist under your current profile, instead of all 11
possible VM names.

The lab's Vagrantfile supports both KVM/libvirt and VirtualBox; this
manager mirrors that with --provider, VAGRANT_DEFAULT_PROVIDER, or an
OS-based default (libvirt on Linux, virtualbox elsewhere) -- see
resolve_provider() for the exact precedence, which matches the
Vagrantfile's own current_provider() logic.

Usage:
    python3 vagrant_manager.py
    python3 vagrant_manager.py --list
    python3 vagrant_manager.py up web db
    python3 vagrant_manager.py status

    LAB_PROFILE=ad python3 vagrant_manager.py --list
    LAB_PROFILE=ai python3 vagrant_manager.py up llm01
    LAB_PROFILE=web python3 vagrant_manager.py up juice-shop
    LAB_PROFILE=cloud python3 vagrant_manager.py up cloud-pentest
    LAB_PROFILE=full python3 vagrant_manager.py up print01

    python3 vagrant_manager.py up --provider virtualbox
    VAGRANT_DEFAULT_PROVIDER=virtualbox python3 vagrant_manager.py up

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

# Must mirror the Vagrantfile's own defaults (see the "LAB PROFILES" block
# near the top of the Vagrantfile). If those ever change, update here too.
LAB_PROFILE_ENV = "LAB_PROFILE"
DEFAULT_LAB_PROFILE = "ad"
# Core VMs are available in every lab profile.
ALWAYS_ON_VMS = ("kali", "dc01")

ACTIONS = {
    "1": ("up", "Bring VM(s) up"),
    "2": ("halt", "Halt VM(s)"),
    "3": ("reload", "Reload VM(s)"),
    "4": ("provision", "Re-run provisioning"),
    "5": ("destroy", "Destroy VM(s)"),
    "6": ("ssh", "SSH into a VM"),
    "7": ("status", "Show status"),
    "8": ("list_all", "List all lab VMs"),
    "9": ("switch_attacker_box", "Switch attacker box (Kali/Parrot/custom)"),
    "q": ("quit", "Quit"),
}

# Known attacker-box presets offered by "Switch attacker box". Anything
# else can still be typed in via the "custom" option.
ATTACKER_BOX_PRESETS = {
    "kali": (None, None),  # None clears the override -> Vagrantfile default
    "parrot": ("ParrotSec/Parrot-security-7.3-libvirt-amd64", "7.3"),
}


@dataclass(frozen=True)
class VmAction:
    """Result of a Vagrant operation."""

    name: str
    ok: bool
    detail: str = ""


@dataclass(frozen=True)
class VmTarget:
    """
    A VM selected for an operation.

    profile_override is set only when the user picked a VM outside the
    current LAB_PROFILE and explicitly agreed to run this one action
    under the profile that includes it. It is scoped to a single
    `vagrant` subprocess call, not the whole session.
    """

    name: str
    profile_override: str | None = None


def find_vagrantfile() -> Path | None:
    """Find a Vagrantfile in the current directory or its parents."""
    here = Path.cwd()

    for directory in (here, *here.parents):
        for name in VAGRANTFILE_CANDIDATES:
            vagrantfile = directory / name

            if vagrantfile.is_file():
                return vagrantfile

    return None


def discover_vms(vagrantfile: Path) -> list[str]:
    """
    Discover VM names from the Vagrantfile.

    First tries the common:

        config.vm.define "name"

    pattern. If no VM definitions are found, falls back to
    `vagrant status`.
    """
    try:
        text = vagrantfile.read_text(
            encoding="utf-8",
            errors="ignore",
        )
    except OSError as exc:
        console.print(
            f"[yellow]Warning:[/yellow] Unable to read "
            f"{vagrantfile}: {exc}"
        )
        return []

    names = re.findall(
        r"""config\.vm\.define\s+["']([\w.-]+)["']""",
        text,
    )

    if names:
        return list(dict.fromkeys(names))

    return discover_vms_from_status(vagrantfile)


def discover_vms_from_status(vagrantfile: Path) -> list[str]:
    """Discover VM names using `vagrant status`."""
    if not shutil.which("vagrant"):
        return []

    try:
        result = subprocess.run(
            ["vagrant", "status"],
            cwd=vagrantfile.parent,
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError):
        return []

    if result.returncode != 0:
        return []

    names: list[str] = []

    # Typical output:
    #
    # web                       not created (virtualbox)
    # db                        running (virtualbox)
    #
    status_pattern = re.compile(
        r"^\s*([\w.-]+)\s+"
        r"(not created|running|poweroff|saved|aborted|"
        r"stopping|starting|unknown)\b",
        re.IGNORECASE,
    )

    for line in result.stdout.splitlines():
        match = status_pattern.match(line)

        if match:
            names.append(match.group(1))

    return list(dict.fromkeys(names))


def parse_lab_profiles(vagrantfile: Path) -> dict[str, list[str]] | None:
    """
    Parse the LAB_PROFILES hash out of the Vagrantfile, e.g.:

        LAB_PROFILES = {
          'minimal' => %w[win10],
          'ad'      => %w[db01 ca01-esc win10 linux01],
          ...
        }.freeze

    Returns None if no LAB_PROFILES block is found. Older Vagrantfiles
    (or other labs without profile support) are handled by treating
    every discovered VM as always active, preserving prior behavior.
    """
    try:
        text = vagrantfile.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None

    block = re.search(r"LAB_PROFILES\s*=\s*\{(.*?)\n\}", text, re.S)

    if not block:
        return None

    profiles: dict[str, list[str]] = {}

    for name, vm_list in re.findall(
        r"""['"]([\w-]+)['"]\s*=>\s*%w\[([^\]]*)\]""",
        block.group(1),
    ):
        profiles[name] = vm_list.split()

    return profiles or None


def resolve_active_vms(
    vagrantfile: Path,
    discovered: list[str],
) -> tuple[set[str], str, bool]:
    """
    Determine which discovered VM names actually exist under the current
    LAB_PROFILE, mirroring the Vagrantfile's own ENV.fetch('LAB_PROFILE', ...)
    default and validation logic.

    Returns (active_vm_names, resolved_profile_name, profiles_supported).
    If the Vagrantfile has no LAB_PROFILES block, profiles_supported is
    False and every discovered VM is treated as active.
    """
    profiles = parse_lab_profiles(vagrantfile)

    if profiles is None:
        return set(discovered), "", False

    requested = os.environ.get(LAB_PROFILE_ENV, DEFAULT_LAB_PROFILE).lower()

    if requested not in profiles:
        console.print(
            f"[yellow]Warning:[/yellow] LAB_PROFILE='{requested}' is not "
            f"one of {sorted(profiles)}. Vagrant itself will raise an "
            f"error if you try to use it as-is; for this menu, falling "
            f"back to '{DEFAULT_LAB_PROFILE}'."
        )
        requested = (
            DEFAULT_LAB_PROFILE
            if DEFAULT_LAB_PROFILE in profiles
            else next(iter(profiles))
        )

    active = set(ALWAYS_ON_VMS) | set(profiles.get(requested, []))
    return active, requested, True


def profile_hint(vagrantfile: Path, vm: str) -> str:
    """Return the profiles that include a VM."""
    profiles = parse_lab_profiles(vagrantfile) or {}
    hits = [name for name, vm_list in profiles.items() if vm in vm_list]
    if not hits:
        return ""
    return ", ".join(f"LAB_PROFILE={name}" for name in hits)


def best_override_profile(vagrantfile: Path, vm: str) -> str | None:
    """
    Pick the most-scoped LAB_PROFILE that includes `vm`.

    Prefers a narrower named profile (e.g. 'web') over 'full' when a VM
    belongs to both, so an assisted one-off run doesn't unnecessarily
    widen the resource footprint beyond what's needed for that VM.
    """
    profiles = parse_lab_profiles(vagrantfile) or {}
    hits = sorted(name for name, vm_list in profiles.items() if vm in vm_list)

    if not hits:
        return None

    narrower = [name for name in hits if name != "full"]
    return narrower[0] if narrower else hits[0]


def require_vagrant() -> bool:
    """Check whether Vagrant is available on PATH."""
    if shutil.which("vagrant"):
        return True

    console.print(
        "[bold red]Error:[/bold red] 'vagrant' was not found on PATH. "
        "Install Vagrant or activate the environment that provides it."
    )
    return False


def run_vagrant(
    action: str,
    vm: str | None,
    vagrantfile: Path,
    extra_args: list[str] | None = None,
    profile_override: str | None = None,
) -> VmAction:
    """
    Run a Vagrant subcommand with live output.

    Commands are always executed from the directory containing
    the discovered Vagrantfile.

    Uses the provider resolved into SELECTED_PROVIDER (see
    resolve_provider()). For "up" and "reload" -- the only actions where
    provider selection actually matters, since other actions operate on
    an already-created machine tied to whichever provider created it --
    an explicit --provider flag is passed on the command line. This
    matches Vagrant's own precedence (CLI flag beats
    VAGRANT_DEFAULT_PROVIDER) and mirrors the Vagrantfile's own
    current_provider() detection, so the two always agree.

    profile_override, if given, is applied only to this subprocess's
    environment (via a copy of os.environ) so a single assisted-switch
    action doesn't change LAB_PROFILE for the rest of the session.
    """
    cmd = ["vagrant", action]

    if action in ("up", "reload"):
        cmd.extend(["--provider", SELECTED_PROVIDER])

    if vm:
        cmd.append(vm)

    if extra_args:
        cmd.extend(extra_args)

    label = vm or "(all)"

    env = {**os.environ, "VAGRANT_DEFAULT_PROVIDER": SELECTED_PROVIDER}
    if profile_override:
        env[LAB_PROFILE_ENV] = profile_override
        console.print(
            f"[dim]Running this action with {LAB_PROFILE_ENV}="
            f"{profile_override} (this session stays on its own "
            f"profile otherwise).[/dim]"
        )

    console.rule(
        f"[bold cyan]vagrant {action}[/bold cyan] {label}"
    )

    try:
        result = subprocess.run(
            cmd,
            cwd=vagrantfile.parent,
            check=False,
            env=env,
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
        console.print("[yellow]Interrupted by user.[/yellow]")
        return VmAction(
            name=label,
            ok=False,
            detail="interrupted",
        )

    if result.returncode == 0:
        return VmAction(name=label, ok=True)

    return VmAction(
        name=label,
        ok=False,
        detail=f"exit code {result.returncode}",
    )


def print_results(results: list[VmAction]) -> None:
    """Display operation results in a Rich table."""
    table = Table(
        title="Result",
        show_lines=False,
    )

    table.add_column("VM")
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


def show_status(vagrantfile: Path) -> bool:
    """Run `vagrant status` from the Vagrantfile directory."""
    console.rule("[bold cyan]vagrant status[/bold cyan]")

    try:
        result = subprocess.run(
            ["vagrant", "status"],
            cwd=vagrantfile.parent,
            check=False,
        )
    except FileNotFoundError:
        console.print(
            "[bold red]Error:[/bold red] Vagrant was not found."
        )
        return False
    except OSError as exc:
        console.print(
            f"[bold red]Error:[/bold red] Unable to run Vagrant: {exc}"
        )
        return False
    except KeyboardInterrupt:
        console.print("[yellow]Interrupted by user.[/yellow]")
        return False

    return result.returncode == 0


def pick_vms(
    vms: list[str],
    active: set[str],
    vagrantfile: Path,
) -> list[VmTarget] | None:
    """
    Prompt the user to pick one, several, or all (active-profile) VMs.

    Picking a VM outside the current LAB_PROFILE doesn't just skip it:
    the user is asked whether to run that one action under the profile
    that includes it (see best_override_profile / VmTarget). Declining
    skips that VM; accepting scopes the profile switch to that single
    `vagrant` call only, leaving the rest of the session unaffected.

    Returns None if the user's selection resolved to nothing runnable
    (nothing picked, or every excluded pick was declined); callers must
    treat None as "cancel", not "operate on everything".
    """
    if not vms:
        console.print(
            "[yellow]No VMs discovered; "
            "will run against all VMs.[/yellow]"
        )
        return []

    console.print("\n[bold]Available VMs:[/bold]")

    for index, name in enumerate(vms, start=1):
        if name in active:
            console.print(f"  {index}. {name}")
        else:
            hint = profile_hint(vagrantfile, name)
            suffix = f" (available via {hint})" if hint else " (not in current LAB_PROFILE)"
            console.print(f"  {index}. [dim]{name}[/dim][yellow]{suffix}[/yellow]")

    console.print(
        f"  a. all  [dim](the {len(active)} VM(s) in your current LAB_PROFILE)[/dim]"
    )

    choice = Prompt.ask(
        "Select VM number(s) (comma-separated) or 'a' for all",
        default="a",
    )

    if choice.strip().lower() == "a":
        return [VmTarget(name) for name in vms if name in active]

    selected: list[VmTarget] = []
    declined: list[str] = []
    seen: set[str] = set()

    for part in choice.split(","):
        part = part.strip()

        if not part.isdigit():
            continue

        index = int(part)

        if not (1 <= index <= len(vms)):
            continue

        name = vms[index - 1]

        if name in seen:
            continue

        if name in active:
            selected.append(VmTarget(name))
            seen.add(name)
            continue

        override = best_override_profile(vagrantfile, name)

        if override is None:
            console.print(
                f"[yellow]'{name}' isn't assigned to any LAB_PROFILE "
                f"-- skipping.[/yellow]"
            )
            declined.append(name)
            continue

        if Confirm.ask(
            f"'{name}' requires LAB_PROFILE={override} (this session "
            f"is on a different profile). Run this one action with "
            f"LAB_PROFILE={override}?",
            default=False,
        ):
            selected.append(VmTarget(name, profile_override=override))
            seen.add(name)
        else:
            declined.append(name)

    if declined:
        console.print(
            "[yellow]Not running for:[/yellow] " + ", ".join(declined)
        )

    if not selected:
        if declined:
            console.print("[yellow]Cancelling this action.[/yellow]")
            return None

        console.print(
            "[yellow]No valid selection made; "
            "defaulting to active-profile VMs.[/yellow]"
        )
        return [VmTarget(name) for name in vms if name in active]

    return selected


def validate_vm_names(
    requested: list[str],
    discovered: list[str],
    active: set[str],
    profile: str,
    supported: bool,
    vagrantfile: Path,
) -> list[str]:
    """
    Validate explicitly supplied VM names.

    When LAB_PROFILES are supported, explicitly requested VMs must also be
    active in the current LAB_PROFILE. This keeps command-line operations
    consistent with the interactive manager and the Vagrantfile.
    """
    if not requested or not discovered:
        return requested

    known = set(discovered)
    unknown = [name for name in requested if name not in known]

    if unknown:
        console.print(
            "[bold red]Error:[/bold red] Unknown VM(s): "
            + ", ".join(unknown)
        )
        console.print(
            "[dim]Known VMs:[/dim] " + ", ".join(discovered)
        )
        return []

    if supported:
        excluded = [name for name in requested if name not in active]
        if excluded:
            console.print(
                f"[bold red]Error:[/bold red] VM(s) not available "
                f"under LAB_PROFILE='{profile}': "
                + ", ".join(excluded)
            )
            for name in excluded:
                hint = profile_hint(vagrantfile, name)
                if hint:
                    console.print(
                        f"[yellow]{name}:[/yellow] use {hint}"
                    )
                else:
                    console.print(
                        f"[yellow]{name}:[/yellow] not assigned to a profile"
                    )
            return []

    return list(dict.fromkeys(requested))


def run_targets(
    action: str,
    vagrantfile: Path,
    targets: list[VmTarget],
    extra_args: list[str] | None = None,
) -> list[VmAction]:
    """Run `action` across each VmTarget, or the whole env if targets is empty."""
    targets_to_run: list[VmTarget | None] = targets or [None]

    return [
        run_vagrant(
            action,
            target.name if target else None,
            vagrantfile,
            extra_args=extra_args,
            profile_override=target.profile_override if target else None,
        )
        for target in targets_to_run
    ]


def interactive_menu(
    vms: list[str],
    active: set[str],
    profile: str,
    supported: bool,
    vagrantfile: Path,
) -> None:
    """Run the interactive Vagrant manager."""
    if not require_vagrant():
        return

    while True:
        box_suffix = (
            f" | Attacker box: {os.environ['KALI_BOX']}"
            if os.environ.get("KALI_BOX")
            else ""
        )
        if supported:
            excluded = [name for name in vms if name not in active]
            menu_title = (
                f"Vagrant Lab Manager -- Provider: {SELECTED_PROVIDER} | "
                f"Profile: {profile} | "
                f"Active: {len(active)} | Excluded: {len(excluded)}"
                f"{box_suffix}"
            )
        else:
            menu_title = f"Vagrant Lab Manager -- Provider: {SELECTED_PROVIDER}{box_suffix}"

        console.print(
            Panel.fit(
                "\n".join(
                    f"{key}. {label}"
                    for key, (_, label) in ACTIONS.items()
                ),
                title=menu_title,
                border_style="cyan",
            )
        )

        choice = Prompt.ask(
            "Choose an action",
            choices=list(ACTIONS.keys()),
            default="7",
        )

        action, _ = ACTIONS[choice]

        if action == "switch_attacker_box":
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
                continue

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
                        f"[green]Attacker box set to {box} @ "
                        f"{version}.[/green]\n"
                        "[yellow]Unverified against this repo's "
                        "Kali-specific guides -- confirm the box/version "
                        "exists on Vagrant Cloud for your provider "
                        "before relying on it.[/yellow]"
                    )
            else:  # custom
                custom_box = Prompt.ask(
                    "Box (org/name)",
                    default=os.environ.get("KALI_BOX", ""),
                )
                if not custom_box:
                    console.print(
                        "[yellow]No box entered -- leaving the current "
                        "setting unchanged.[/yellow]"
                    )
                    continue

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
                "[dim]Takes effect on the next 'up'/'reload' for kali -- "
                "an already-running kali VM keeps its current box until "
                "it's destroyed and brought up again.[/dim]"
            )
            continue

        if action == "list_all":
            table = Table(title="All lab VMs")
            table.add_column("VM")
            table.add_column("Status")
            table.add_column("Available profiles")

            profiles = parse_lab_profiles(vagrantfile) or {}

            for name in vms:
                owning = [
                    p_name
                    for p_name, p_vms in profiles.items()
                    if name in p_vms or name in ALWAYS_ON_VMS
                ]
                table.add_row(
                    name,
                    "[green]active[/green]"
                    if name in active
                    else "[yellow]excluded[/yellow]",
                    ", ".join(owning) if owning else "-",
                )

            console.print(table)
            continue

        if action == "quit":
            console.print("Bye.")
            return

        if action == "status":
            show_status(vagrantfile)
            continue

        if action == "ssh":
            targets = pick_vms(vms, active, vagrantfile)

            if targets is None:
                console.print("[yellow]Cancelled.[/yellow]")
                continue

            if len(targets) != 1:
                console.print(
                    "[yellow]SSH requires exactly one VM. "
                    "Pick a single number.[/yellow]"
                )
                continue

            run_vagrant(
                "ssh",
                targets[0].name,
                vagrantfile,
                profile_override=targets[0].profile_override,
            )
            continue

        if action == "destroy":
            targets = pick_vms(vms, active, vagrantfile)

            if targets is None:
                console.print("[yellow]Cancelled.[/yellow]")
                continue

            names = (
                ", ".join(t.name for t in targets)
                if targets
                else "ALL VMs"
            )

            if not Confirm.ask(
                f"[bold red]Really destroy {names}?[/bold red]",
                default=False,
            ):
                console.print("Cancelled.")
                continue

            results = run_targets(
                "destroy",
                vagrantfile,
                targets,
                extra_args=["-f"],
            )

            print_results(results)
            continue

        targets = pick_vms(vms, active, vagrantfile)

        if targets is None:
            console.print("[yellow]Cancelled.[/yellow]")
            continue

        results = run_targets(action, vagrantfile, targets)

        print_results(results)


def main() -> int:
    """Program entry point."""
    parser = argparse.ArgumentParser(
        description="Manage lab Vagrant VMs."
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
        help="Action to run non-interactively.",
    )

    parser.add_argument(
        "vms",
        nargs="*",
        help="VM names to target (default: all).",
    )

    parser.add_argument(
        "--list",
        action="store_true",
        help="List discovered VMs and exit.",
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
    # this run makes (interactive or one-shot) inherits it via the
    # existing `env = {**os.environ, ...}` copy in run_vagrant().
    if args.kali_box:
        os.environ["KALI_BOX"] = args.kali_box
    if args.kali_box_version:
        os.environ["KALI_BOX_VERSION"] = args.kali_box_version

    vagrantfile = find_vagrantfile()

    if vagrantfile is None:
        console.print(
            "[bold red]Error:[/bold red] No Vagrantfile found "
            "in this directory or any parent."
        )
        return 1

    console.print(
        f"[dim]Vagrantfile:[/dim] {vagrantfile}"
    )
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

    vms = discover_vms(vagrantfile)
    active, profile, supported = resolve_active_vms(vagrantfile, vms)

    if args.list:
        if vms:
            for vm in vms:
                if not supported or vm in active:
                    console.print(vm)
                else:
                    hint = profile_hint(vagrantfile, vm)
                    suffix = f" (needs {hint})" if hint else " (excluded)"
                    console.print(f"{vm}{suffix}")
        else:
            console.print(
                "[yellow]No VMs discovered.[/yellow]"
            )
        return 0

    if args.action:
        if not require_vagrant():
            return 1

        if args.action == "status":
            return 0 if show_status(vagrantfile) else 1

        targets = validate_vm_names(
            args.vms,
            vms,
            active,
            profile,
            supported,
            vagrantfile,
        )

        if args.vms and not targets:
            return 1

        default_targets = (
            [name for name in vms if name in active] if supported else vms
        )
        targets_to_run = targets or default_targets or [None]

        extra = (
            ["-f"]
            if args.action == "destroy"
            else None
        )

        results = [
            run_vagrant(
                args.action,
                vm,
                vagrantfile,
                extra_args=extra,
            )
            for vm in targets_to_run
        ]

        print_results(results)

        return 1 if any(not result.ok for result in results) else 0

    interactive_menu(
        vms,
        active,
        profile,
        supported,
        vagrantfile,
    )

    return 0


if __name__ == "__main__":
    sys.exit(main())
