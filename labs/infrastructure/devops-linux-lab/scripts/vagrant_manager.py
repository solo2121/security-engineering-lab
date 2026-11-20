#!/usr/bin/env python3
"""
vagrant_manager.py

Interactive manager for the lab's Vagrant VMs.

Provides a Rich-based Python CLI while preserving the behavior
of the original Bash manager.

Features:
- Fixed HARBOR_PASS environment propagation
- Session cache prevents repeated Harbor password prompts
- Start (T) does not require Harbor credentials
- Harbor password is requested only for the VMs that use Harbor
  (see HARBOR_VMS); Linux labs, workers, Ansible nodes and the Kind/K3d
  labs never prompt for it
- Provisioning actions prompt only once per session
- CI/CD server group included
- Supports both KVM/libvirt and VirtualBox against the lab's unified
  Vagrantfile (select with --provider, VAGRANT_MANAGER_PROVIDER, or
  VAGRANT_DEFAULT_PROVIDER; see resolve_provider() for precedence)
- Safe non-interactive destroy behavior

Requires:
    rich

Install:
    pip install rich
"""

from __future__ import annotations

import argparse
import getpass
import os
import platform
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

# ========================== RESULT TYPE ==========================


@dataclass
class VmAction:
    """Result of a Vagrant operation."""

    name: str
    ok: bool
    detail: str = ""


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


# Curated inventory for UI grouping and batch actions.
#
# The Vagrantfile may define only a profile subset at runtime.
# Keep the full lab inventory visible and use Vagrant status to
# determine the current state of each machine.

VM_GROUPS = {
    "DEVOPS": ("devops-1",),
    "WORKERS": ("worker-1", "worker-2"),
    "ANSIBLE NODES": ("node1", "node2"),
    "LINUX LABS": (
        "ubuntu-lab",
        "rocky-lab",
        "alma-lab",
        "suse-lab",
    ),
    "MODERN LABS": ("kind-lab", "k3d-lab"),
    "CI/CD SERVER": ("cicd-server",),
}

ALL_VMS = tuple(
    vm
    for group in VM_GROUPS.values()
    for vm in group
)

# VMs whose provisioning actually uses the Harbor admin password.
#
# devops-1 installs Harbor itself; cicd-server is a Harbor client that
# logs in to push images. Every other VM (Linux labs, workers, Ansible
# nodes, Kind/K3d) never touches Harbor, so provisioning them must not
# ask for the password. Keep in sync with the Vagrantfile's HARBOR_VMS.
HARBOR_VMS = ("devops-1", "cicd-server")


def vm_needs_harbor(vm: str | None) -> bool:
    """
    Return True if provisioning `vm` requires the Harbor password.

    vm=None means "every VM" (no explicit target), which always includes
    the Harbor VMs.
    """
    return vm is None or vm in HARBOR_VMS

# Known Vagrant states.
_VAGRANT_STATES = (
    "not created",
    "running",
    "poweroff",
    "saved",
    "aborted",
    "unknown",
    "stopping",
    "preparing",
)

STATE_ICONS = {
    "running": "[green]▶[/green]",
    "poweroff": "[red]■[/red]",
    "shutoff": "[red]■[/red]",
    "not_created": "[yellow]○[/yellow]",
    "saved": "[yellow]⏸[/yellow]",
    "aborted": "[red]![/red]",
    "stopping": "[yellow]…[/yellow]",
    "preparing": "[yellow]…[/yellow]",
    "unknown": "[bright_black]?[/bright_black]",
    "default": "[bright_black]?[/bright_black]",
}

# ========================== SESSION STATE ==========================

# Prevent repeated Harbor password prompts during the same process.

HARBOR_PROMPT_DONE = False
HARBOR_PASS: str | None = os.environ.get("HARBOR_PASS")

# Resolved once in main() via resolve_provider() and read by every
# run_vagrant() call afterward. Set to a safe default here so any code
# path that runs before main() (e.g. tests importing this module) still
# has a defined value rather than None.
SELECTED_PROVIDER: str = "libvirt"


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


# ========================== VM STATUS ==========================


def get_machine_states(
    vagrantfile: Path,
) -> dict[str, str]:
    """
    Ask Vagrant for machine-readable state information.

    Vagrant's machine-readable output is more reliable than parsing
    the human-readable status table.

    The Vagrantfile only defines the VMs selected by LAB_PROFILE (the
    default "minimal" profile defines just devops-1 and worker-1), and
    `vagrant status` only reports defined machines. The query therefore
    runs with every VM defined; otherwise running VMs outside the active
    profile (ubuntu-lab, rocky-lab, ...) are missing from the output and
    are wrongly displayed as "not_created".
    """
    states: dict[str, str] = {}

    if not shutil.which("vagrant"):
        return states

    try:
        result = subprocess.run(
            [
                "vagrant",
                "status",
                "--machine-readable",
            ],
            cwd=vagrantfile.parent,
            env=build_vagrant_environment(include_all_vms=True),
            capture_output=True,
            text=True,
            check=False,
            stdin=subprocess.DEVNULL,
        )
    except (FileNotFoundError, OSError):
        return states

    if result.returncode != 0:
        return states

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

    return states


# ========================== HARBOR PASSWORD HANDLING ==========================


def ensure_harbor_pass() -> bool:
    """
    Ensure a Harbor password is available.

    The password is kept only in process memory and passed to Vagrant
    through the child process environment.
    """
    global HARBOR_PASS

    if HARBOR_PASS:
        return True

    console.print(
        Panel.fit(
            "[bold]HARBOR REGISTRY PASSWORD REQUIRED[/bold]\n\n"
            "Harbor container registry needs an admin password.\n"
            "This is required for provisioning the main cluster.\n\n"
            "You can also set it in advance:\n"
            "[cyan]export HARBOR_PASS='YourStrongPassword'[/cyan]",
            border_style="yellow",
        )
    )

    while True:
        try:
            password = getpass.getpass(
                "Enter Harbor admin password: "
            )
        except (KeyboardInterrupt, EOFError):
            console.print(
                "\n[yellow]Password entry cancelled.[/yellow]"
            )
            return False

        if not password:
            console.print(
                "[bold red]ERROR: Password cannot be empty.[/bold red]"
            )
            continue

        if len(password) < 8:
            console.print(
                "[yellow]WARNING: Password is less than "
                "8 characters.[/yellow]"
            )

            if not Confirm.ask(
                "Continue?",
                default=False,
            ):
                return False

        try:
            password_confirm = getpass.getpass(
                "Confirm password: "
            )
        except (KeyboardInterrupt, EOFError):
            console.print(
                "\n[yellow]Password entry cancelled.[/yellow]"
            )
            return False

        if password != password_confirm:
            console.print(
                "[bold red]ERROR: Passwords do not match.[/bold red]"
            )
            continue

        HARBOR_PASS = password

        console.print(
            "[green]Password configured successfully.[/green]"
        )

        return True


def ensure_harbor_pass_once() -> bool:
    """Prompt for Harbor credentials at most once per session."""
    global HARBOR_PROMPT_DONE

    if HARBOR_PROMPT_DONE:
        return HARBOR_PASS is not None

    if not ensure_harbor_pass():
        return False

    HARBOR_PROMPT_DONE = True
    return True


# ========================== VAGRANT EXECUTION ==========================


def require_vagrant() -> bool:
    """Return True if Vagrant is available on PATH."""
    if shutil.which("vagrant"):
        return True

    console.print(
        "[bold red]Error:[/bold red] 'vagrant' was not found on PATH. "
        "Install Vagrant or activate the environment that provides it."
    )

    return False


def build_vagrant_environment(
    include_all_vms: bool = False,
) -> dict[str, str]:
    """
    Build the environment used by child Vagrant processes.

    HARBOR_PASS is intentionally passed through the environment rather
    than command-line arguments so it does not appear in process args.

    When include_all_vms is True, LAB_PROFILE is forced to "full" so the
    Vagrantfile defines every lab VM. Use it for commands that must see
    machines regardless of the active profile (status, halt-all).
    """
    env = os.environ.copy()

    env["VAGRANT_DEFAULT_PROVIDER"] = SELECTED_PROVIDER

    if include_all_vms:
        env["LAB_PROFILE"] = "full"

    if HARBOR_PASS:
        env["HARBOR_PASS"] = HARBOR_PASS

    return env


def run_vagrant(
    action: str,
    vagrantfile: Path,
    vm: str | None = None,
    extra_args: list[str] | None = None,
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

    SSH keeps interactive stdin. Other commands receive /dev/null
    so unexpected prompts cannot block the manager.
    """
    cmd = ["vagrant", action]

    if action in ("up", "reload"):
        cmd.extend(["--provider", SELECTED_PROVIDER])

    if vm:
        cmd.append(vm)

    if extra_args:
        cmd.extend(extra_args)

    label = vm or "(all)"

    console.rule(
        f"[bold cyan]vagrant {action}[/bold cyan] {label}"
    )

    # Status and halt without an explicit VM must cover every machine,
    # not only the ones in the active LAB_PROFILE.
    env = build_vagrant_environment(
        include_all_vms=(
            vm is None and action in ("status", "halt")
        )
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
            detail="",
        )

    return VmAction(
        name=label,
        ok=False,
        detail=f"exit code {result.returncode}",
    )


# ========================== UI ==========================


def show_main_menu(
    states: dict[str, str],
) -> dict[str, str]:
    """Render the main menu and return selection-to-VM mapping."""
    console.clear()

    console.print(
        Panel.fit(
            "[bold white]VAGRANT LAB MANAGER v8.2[/bold white]\n"
            f"[dim]Provider: {SELECTED_PROVIDER}[/dim]",
            border_style="blue",
        )
    )

    table = Table(
        show_header=False,
        box=None,
        padding=(0, 1, 0, 1),
    )

    table.add_column(
        "ID",
        style="cyan",
        width=5,
    )
    table.add_column(
        "VM",
        style="white",
        width=15,
    )
    table.add_column(
        "State",
        width=20,
    )

    index = 1
    options: dict[str, str] = {}

    for group_name, configured_vms in VM_GROUPS.items():
        table.add_row(
            "",
            f"[bold purple]{group_name}[/bold purple]",
            "",
            style="underline",
        )

        for vm in configured_vms:
            state = states.get(
                vm,
                "not_created",
            )

            icon = STATE_ICONS.get(
                state,
                STATE_ICONS["default"],
            )

            table.add_row(
                f"[{index:02d}]",
                vm,
                f"{icon} {state}",
            )

            options[str(index)] = vm
            index += 1

        table.add_row()

    console.print(table)

    console.print(
        "[cyan][A] Start All (provision)  "
        "[V] DevOps (provision)[/cyan]"
    )
    console.print(
        "[cyan][W] Workers (no provision)   "
        "[N] Ansible (no provision)[/cyan]"
    )
    console.print(
        "[cyan][L] Linux Labs (no provision) "
        "[M] Modern (no provision)[/cyan]"
    )
    console.print(
        "[cyan][C] CI/CD Server (no provision) "
        "[B] Halt All[/cyan]"
    )
    console.print(
        "[cyan][R] Refresh  [Q] Quit[/cyan]"
    )
    console.print(
        "[bright_black]Note: Harbor password only required "
        "once per session for provisioning[/bright_black]"
    )

    return options


def vm_menu(
    vagrantfile: Path,
    vm: str,
) -> None:
    """Display the individual VM management menu."""
    while True:
        states = get_machine_states(
            vagrantfile
        )

        state = states.get(
            vm,
            "not_created",
        )

        console.clear()

        console.print(
            Panel.fit(
                f"[bold white]VM MANAGEMENT: {vm}[/bold white]",
                border_style="blue",
            )
        )

        console.print(
            f"VM:    [cyan]{vm}[/cyan]"
        )
        console.print(
            f"State: {state}"
        )

        needs_harbor = vm_needs_harbor(vm)

        # Only VMs that use Harbor ever ask for its password.
        pw_note = (
            "(password needed once)"
            if needs_harbor
            else "(no password)"
        )

        if not needs_harbor:
            console.print(
                "Harbor: [bright_black]not used by this VM[/bright_black]"
            )
        elif HARBOR_PASS and HARBOR_PROMPT_DONE:
            console.print(
                "Harbor: [green]configured (session)[/green]"
            )
        elif HARBOR_PASS:
            console.print(
                "Harbor: [green]configured[/green]"
            )
        else:
            console.print(
                "Harbor: [yellow]not set "
                "(only needed for provision)[/yellow]"
            )

        console.print(
            "\n[cyan][S] SSH (no password needed)[/cyan]"
        )
        console.print(
            f"[cyan][U] Up with Provision {pw_note}[/cyan]"
        )
        console.print(
            "[cyan][T] Start "
            "(no provision, no password)[/cyan]"
        )
        console.print(
            "[cyan][H] Halt (no password)[/cyan]"
        )
        console.print(
            f"[cyan][R] Reload with Provision {pw_note}[/cyan]"
        )
        console.print(
            f"[cyan][P] Provision only {pw_note}[/cyan]"
        )
        console.print(
            "[cyan][D] Destroy (no password)[/cyan]"
        )
        console.print(
            "[cyan][B] Back[/cyan]"
        )
        console.print(
            "[cyan][Q] Quit[/cyan]"
        )

        choice = Prompt.ask(
            "[bold]Action[/bold]",
            default="B",
        ).upper()

        if choice == "S":
            run_vagrant(
                "ssh",
                vagrantfile,
                vm=vm,
            )

        elif choice == "U":
            if not needs_harbor or ensure_harbor_pass_once():
                run_vagrant(
                    "up",
                    vagrantfile,
                    vm=vm,
                    extra_args=["--provision"],
                )

        elif choice == "T":
            run_vagrant(
                "up",
                vagrantfile,
                vm=vm,
            )

        elif choice == "H":
            run_vagrant(
                "halt",
                vagrantfile,
                vm=vm,
            )

        elif choice == "R":
            if not needs_harbor or ensure_harbor_pass_once():
                run_vagrant(
                    "reload",
                    vagrantfile,
                    vm=vm,
                    extra_args=["--provision"],
                )

        elif choice == "P":
            if not needs_harbor or ensure_harbor_pass_once():
                run_vagrant(
                    "provision",
                    vagrantfile,
                    vm=vm,
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
                )

        elif choice == "B":
            return

        elif choice == "Q":
            return_code = 0
            raise SystemExit(return_code)

        else:
            console.print(
                "[red]Invalid option[/red]"
            )

        Prompt.ask(
            "[bright_black]Press Enter to continue...[/bright_black]",
            default="",
        )


# ========================== GROUP ACTIONS ==========================


def start_group(
    vagrantfile: Path,
    group_key: str,
) -> list[VmAction]:
    """
    Start a selected VM group.

    Preserves v8.1 behavior:
    - all -> provision
    - DEVOPS -> provision
    - all other groups -> no provisioning
    """
    group_map = {
        "V": "DEVOPS",
        "W": "WORKERS",
        "N": "ANSIBLE NODES",
        "L": "LINUX LABS",
        "M": "MODERN LABS",
        "C": "CI/CD SERVER",
    }

    if group_key == "all":
        if not ensure_harbor_pass_once():
            return []

        result = run_vagrant(
            "up",
            vagrantfile,
            extra_args=["--provision"],
        )

        return [result]

    group_name = group_map.get(group_key)

    if not group_name:
        return []

    vms = VM_GROUPS[group_name]

    provision = group_name == "DEVOPS"

    if provision and not ensure_harbor_pass_once():
        return []

    results: list[VmAction] = []

    for vm in vms:
        if provision:
            console.print(
                f"[yellow]Starting {vm} "
                "(provision)...[/yellow]"
            )

            result = run_vagrant(
                "up",
                vagrantfile,
                vm=vm,
                extra_args=["--provision"],
            )
        else:
            console.print(
                f"[yellow]Starting {vm}...[/yellow]"
            )

            result = run_vagrant(
                "up",
                vagrantfile,
                vm=vm,
            )

        results.append(result)

    return results


def halt_all(
    vagrantfile: Path,
) -> VmAction:
    """Halt all VMs."""
    console.print(
        "[yellow]Halting all VMs...[/yellow]"
    )

    return run_vagrant(
        "halt",
        vagrantfile,
        extra_args=["-f"],
    )


# ========================== CLI HELPERS ==========================


def validate_vm_names(
    requested: list[str],
    states: dict[str, str],
) -> list[str]:
    """
    Validate explicit VM names.

    Vagrant status is preferred because it reflects the active
    Vagrantfile/profile. If status is unavailable, fall back to the
    curated lab inventory.
    """
    if not requested:
        return []

    known = (
        set(states)
        if states
        else set(ALL_VMS)
    )

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

    # Preserve user order while removing duplicates.
    return list(dict.fromkeys(requested))


def print_results(
    results: list[VmAction],
) -> None:
    """Display command results in a Rich table."""
    if not results:
        return

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


# ========================== MAIN ==========================


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
        "--provision",
        action="store_true",
        help="Run Vagrant provisioning with the action.",
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

    args = parser.parse_args()

    global SELECTED_PROVIDER
    SELECTED_PROVIDER = resolve_provider(args.provider)

    # ------------------------------------------------------------------
    # Locate Vagrantfile.
    # ------------------------------------------------------------------

    vagrantfile = find_vagrantfile()

    if vagrantfile is None:
        console.print(
            "[bold red]Error:[/bold red] No Vagrantfile found "
            "in this directory or any parent."
        )

        return 1

    # ------------------------------------------------------------------
    # Verify Vagrant.
    # ------------------------------------------------------------------

    if not require_vagrant():
        return 1

    console.print(
        f"[dim]Provider: [bold]{SELECTED_PROVIDER}[/bold] "
        "(override with --provider or VAGRANT_DEFAULT_PROVIDER)[/dim]"
    )

    # ------------------------------------------------------------------
    # Non-interactive mode.
    # ------------------------------------------------------------------

    if args.action:
        if args.action == "status":
            result = run_vagrant(
                "status",
                vagrantfile,
            )

            return 0 if result.ok else 1

        states = get_machine_states(
            vagrantfile
        )

        targets = validate_vm_names(
            args.vms,
            states,
        )

        if args.vms and not targets:
            return 1

        # Never allow implicit global destruction.
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
                "destroy devops-1 worker-1"
            )

            return 1

        # Only ask for the Harbor password when at least one target
        # uses Harbor (no explicit targets means every VM).
        needs_harbor = not targets or any(
            vm_needs_harbor(vm)
            for vm in targets
        )

        # Determine provisioning behavior.
        if args.action == "provision":
            if needs_harbor and not ensure_harbor_pass_once():
                return 1

            extra = None

        elif (
            args.action in {"up", "reload"}
            and args.provision
        ):
            if needs_harbor and not ensure_harbor_pass_once():
                return 1

            extra = ["--provision"]

        elif args.action == "destroy":
            extra = ["-f"]

        else:
            extra = None

        targets_to_run = targets or [None]

        results = [
            run_vagrant(
                args.action,
                vagrantfile,
                vm=vm,
                extra_args=extra,
            )
            for vm in targets_to_run
        ]

        print_results(results)

        return (
            1
            if any(
                not result.ok
                for result in results
            )
            else 0
        )

    # ------------------------------------------------------------------
    # Interactive mode.
    # ------------------------------------------------------------------

    while True:
        states = get_machine_states(
            vagrantfile
        )

        options = show_main_menu(
            states
        )

        choice = Prompt.ask(
            "[bold]Selection[/bold]",
            default="R",
        )

        if (
            choice.isdigit()
            and choice in options
        ):
            vm_menu(
                vagrantfile,
                options[choice],
            )
            continue

        choice = choice.upper()

        if choice in {
            "A",
            "V",
            "W",
            "N",
            "L",
            "M",
            "C",
        }:
            results = start_group(
                vagrantfile,
                "all" if choice == "A" else choice,
            )

            print_results(results)

        elif choice == "B":
            result = halt_all(
                vagrantfile
            )

            print_results([result])

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
