#!/usr/bin/env python3
"""
enum4linux-menu.py - Interactive wrapper for enum4linux

Description:
    A user-friendly, menu-driven interface for enum4linux that simplifies SMB enumeration.
    Allows selective execution of enum4linux functions with visual feedback on chosen options.
    Handles common enum4linux parameters through an intuitive CLI and interactive menu.

Features:
    - Interactive TUI for selecting enum4linux scan options
    - Supports all major enum4linux switches (-U, -G, -S, etc.)
    - Visual confirmation of selected scan options
    - Built-in parameter validation
    - Clear screen management for better UX
    - Supports authenticated scans (username/password/domain)
    - Configurable connection timeout

Requirements:
    - Python 3.7+
    - enum4linux installed and in $PATH
    - smbclient, nmblookup, and other SMB tools (normally bundled with enum4linux)

Author: Solo
License: MIT
Version: 1.0.0
Last Modified: 2025-07-21

Usage Examples:
    Basic scan: ./enum4linux-menu.py -t 192.168.1.100
    Authenticated scan: ./enum4linux-menu.py -t 192.168.1.100 -u admin -p password -d WORKGROUP
    Custom timeout: ./enum4linux-menu.py -t 192.168.1.100 --timeout 60

Known Limitations:
    - Doesn't save scan results automatically (pipe output manually)
    - Limited error handling for network timeouts
    - No color output support (yet)

Troubleshooting:
    If you get "enum4linux not found" errors:
    1. Install enum4linux: sudo apt install enum4linux (Debian/Ubuntu)
    2. Ensure it's in your $PATH: which enum4linux
    3. Check dependencies: smbclient, nmblookup, rpcclient

To Do:
    - Add output file saving option
    - Implement color output
    - Add batch mode for multiple targets
"""

import argparse
import os
import shlex
import shutil
import subprocess
import sys
from typing import List, Tuple

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------
VERSION = "1.0.0"
AUTHOR = "Solo"
BANNER_COLOR = False  # Future feature

# ------------------------------------------------------------------
# Banner
# ------------------------------------------------------------------
BANNER = r"""
 ____ ____ ____ ____ ____ ____ ____ ____ ____ ____ ____ ____ ____ ____
||e |||n |||u |||m |||4 |||l |||i |||n |||u |||x |||  |||M |||E |||N |||U ||
||__|||__|||__|||__|||__|||__|||__|||__|||__|||__|||__|||__|||__|||__|||__||
|/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|
Interactive wrapper for the classic SMB enumeration tool.
v{version} | {author}
""".format(version=VERSION, author=AUTHOR)

# ------------------------------------------------------------------
# Available enum4linux switches
# (description, short switch, long switch)
# ------------------------------------------------------------------
OPTIONS: List[Tuple[str, str, str]] = [
    ("Do everything (-a)", "-a", ""),
    ("Enumerate users (-U)", "-U", ""),
    ("Enumerate groups (-G)", "-G", ""),
    ("Enumerate shares (-S)", "-S", ""),
    ("Enumerate passwords policy (-P)", "-P", ""),
    ("Enumerate OS information (-O)", "-O", ""),
    ("Enumerate printers (-i)", "-i", ""),
    ("Enumerate LSA Policy info (-L)", "-L", ""),
    ("Enumerate RID cycling (RID range)", "-r", ""),
    ("Enumerate via brute-force share names (-b)", "-b", ""),
    ("Enumerate via brute-force user names (-B)", "-B", ""),
    ("Enumerate via null session (-n)", "-n", ""),
]

# ------------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------------


def clear_screen() -> None:
    """Clear terminal screen in a cross-platform way."""
    # Fixed literal ("cls"/"clear"); no user input reaches this call.
    os.system("cls" if os.name == "nt" else "clear")  # nosec B605


def print_banner() -> None:
    """Display the program banner."""
    print(BANNER)


def check_enum4linux() -> bool:
    """Check if enum4linux is available in $PATH."""
    return shutil.which("enum4linux") is not None


def ask(prompt: str, valid: List[str]) -> str:
    """
    Prompt user until valid input is received.

    Args:
        prompt: The question to ask
        valid: List of acceptable responses (case-insensitive)

    Returns:
        The user's valid choice
    """
    while True:
        choice = input(prompt).strip().lower()
        if choice in valid:
            return choice
        print(f"Invalid choice. Must be one of: {', '.join(valid)}")


# ------------------------------------------------------------------
# Main interactive menu
# ------------------------------------------------------------------


def interactive_menu(target: str, custom_options: List[str]) -> None:
    """
    Run the interactive menu for selecting enum4linux options.

    Args:
        target: IP/hostname to scan
        custom_options: Pre-configured options from CLI args
    """
    selected = set()

    while True:
        clear_screen()
        print_banner()

        print(f"\nTarget: {target}\n")
        print("Select the checks you want to run. 0 to launch enum4linux.\n")

        for idx, (desc, short, long) in enumerate(OPTIONS, 1):
            marker = "[✓]" if short in selected else "[ ]"
            print(f"{idx:>2}. {marker} {desc}")

        choice = input("\nToggle option (1-{}) or 0 to run: ".format(len(OPTIONS))).strip()

        if choice == "0":
            break
        if choice.isdigit() and 1 <= int(choice) <= len(OPTIONS):
            short_switch = OPTIONS[int(choice) - 1][1]
            if short_switch in selected:
                selected.remove(short_switch)
            else:
                selected.add(short_switch)

    # Build final command line
    cmd = ["enum4linux"] + custom_options + list(selected) + [target]

    print("\n[+] Command that will be executed:")
    print("    " + " ".join(shlex.quote(c) for c in cmd))

    confirm = ask("\nProceed? [y/N]: ", ["y", "n", ""])
    if confirm == "y":
        print("\n" + "=" * 60)
        subprocess.run(cmd)
    else:
        print("\nAborted.")


# ------------------------------------------------------------------
# CLI argument parsing
# ------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    """Parse and validate command line arguments."""
    parser = argparse.ArgumentParser(
        description="Interactive wrapper around enum4linux", formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("-t", "--target", required=True, help="Target IP address / hostname")
    parser.add_argument("-u", "--user", metavar="USER", help="Username (if authentication is needed)")
    parser.add_argument("-p", "--password", metavar="PASS", help="Password (if authentication is needed)")
    parser.add_argument("-d", "--domain", metavar="DOMAIN", help="Domain / workgroup")
    parser.add_argument("--timeout", type=int, default=30, help="Connection timeout in seconds (default: 30)")
    parser.add_argument(
        "-v", "--version", action="version", version=f"%(prog)s {VERSION}", help="Show version information"
    )
    return parser.parse_args()


def build_custom_options(args: argparse.Namespace) -> List[str]:
    """Convert CLI arguments to enum4linux command options."""
    opts = []
    if args.user:
        opts += ["-u", args.user]
    if args.password:
        opts += ["-p", args.password]
    if args.domain:
        opts += ["-w", args.domain]
    if args.timeout:
        opts += ["-T", str(args.timeout)]
    return opts


# ------------------------------------------------------------------
# Main function
# ------------------------------------------------------------------


def main() -> None:
    """Main entry point for the script."""
    args = parse_args()

    if not check_enum4linux():
        print("[!] enum4linux not found in $PATH. Please install it first.")
        print("[!] On Debian/Ubuntu: sudo apt install enum4linux")
        sys.exit(1)

    custom_options = build_custom_options(args)
    interactive_menu(args.target, custom_options)


if __name__ == "__main__":
    main()
# ------------------------------------------------------------------
# End of script
# ------------------------------------------------------------------
# This script is released under the MIT License.
