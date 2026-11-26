#!/usr/bin/env python3

import subprocess
import sys
from colorama import init, Fore, Style
import re
import socket
import os


def validate_ip(ip):
    """Validate if a string is a valid IP address"""
    pattern = r"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
    return re.match(pattern, ip) is not None


def validate_hostname(hostname):
    """Validate if a string is a valid hostname"""
    try:
        socket.gethostbyname(hostname)
        return True
    except (socket.gaierror, UnicodeError):
        return False


def validate_target(target):
    """Validate if target is a valid IP address or hostname"""
    return validate_ip(target) or validate_hostname(target)


def get_network_interfaces():
    """Get list of available network interfaces"""
    try:
        result = subprocess.run(["ip", "-o", "link", "show"], capture_output=True, text=True)
        interfaces = [line.split(":")[1].strip() for line in result.stdout.splitlines()]
        return interfaces
    except Exception:
        # Fallback to common interface names if ip command fails
        return ["eth0", "wlan0", "enp0s3", "en0", "lo"]


# Initialize colorama
init(autoreset=True)


def get_decoys():
    """Prompt user for decoy configuration and return nmap arguments"""
    use_decoys = input(Fore.MAGENTA + "Use decoys to hide your IP? (y/n): ").strip().lower()
    if use_decoys != "y":
        return []

    print(Fore.CYAN + "\nDecoy Options:")
    print(Fore.YELLOW + "1) Enter specific IP addresses")
    print(Fore.YELLOW + "2) Generate random decoys")
    print(Fore.YELLOW + "3) Use ME option (include real IP)")
    decoy_choice = input(Fore.CYAN + "Choose decoy type (1-3): ").strip()

    if decoy_choice == "1":
        decoy_input = input(Fore.CYAN + "Enter decoy IPs separated by commas: ").strip()
        decoys = [d.strip() for d in decoy_input.split(",") if d.strip()]
        valid_decoys = [d for d in decoys if validate_ip(d)]

        if not valid_decoys:
            print(Fore.RED + "No valid IP addresses entered")
            return []

        # Ask if user wants to include their real IP
        include_real = input(Fore.CYAN + "Include your real IP? (y/n): ").strip().lower()
        if include_real == "y":
            valid_decoys.append("ME")

        return ["-D", ",".join(valid_decoys)]

    elif decoy_choice == "2":
        count = input(Fore.CYAN + "Number of random decoys to generate: ").strip()
        if count.isdigit() and int(count) > 0:
            include_real = input(Fore.CYAN + "Include your real IP? (y/n): ").strip().lower()
            decoy_arg = f"RND:{count}"
            if include_real == "y":
                decoy_arg += ",ME"
            return ["-D", decoy_arg]
        else:
            print(Fore.RED + "Invalid number")
            return []

    elif decoy_choice == "3":
        return ["-D", "ME"]

    else:
        print(Fore.RED + "Invalid choice")
        return []


def get_spoof_options():
    """Prompt user for spoof configuration and return nmap arguments"""
    spoof = input(Fore.MAGENTA + "Spoof source IP address? (y/n): ").strip().lower()
    if spoof != "y":
        return []

    # Get available interfaces
    interfaces = get_network_interfaces()

    print(Fore.CYAN + "\nAvailable network interfaces:")
    for i, iface in enumerate(interfaces, 1):
        print(Fore.YELLOW + f"{i}) {iface}")

    # Select interface
    while True:
        try:
            choice = int(input(Fore.CYAN + f"Select interface (1-{len(interfaces)}): ").strip())
            if 1 <= choice <= len(interfaces):
                interface = interfaces[choice - 1]
                break
            else:
                print(Fore.RED + "Invalid selection")
        except ValueError:
            print(Fore.RED + "Please enter a number")

    # Get source IP to spoof
    ip = input(Fore.CYAN + "Enter source IP to spoof: ").strip()
    if not validate_ip(ip):
        print(Fore.RED + "Invalid IP address")
        return []

    return ["-e", interface, "-S", ip, "-Pn"]


def run_nmap(args, target, description="", decoy_args=None, spoof_args=None):
    """Execute nmap command with given arguments.

    decoy_args/spoof_args: pass pre-computed lists to skip the interactive
    evasion prompts (used by complete_scan() so it only asks once for a
    whole batch of scans instead of once per sub-scan). Leave as None for
    the normal single-scan menu flow, which prompts as before.
    """
    if not validate_target(target):
        print(Fore.RED + f"Invalid target: {target}")
        return

    # Get evasion techniques (unless the caller already collected them)
    if decoy_args is None:
        decoy_args = get_decoys()
    if spoof_args is None:
        spoof_args = get_spoof_options()

    # Add evasion options to nmap arguments
    full_args = args + decoy_args + spoof_args

    print(Fore.CYAN + f"\n[+] Running {description} on {target}")
    print(Fore.YELLOW + f"Command: sudo nmap {' '.join(full_args)} {target}\n")

    try:
        result = subprocess.run(["sudo", "nmap", *full_args, target], capture_output=True, text=True)
        print(Fore.GREEN + result.stdout)
        if result.stderr:
            print(Fore.RED + "Errors:\n" + result.stderr)
    except FileNotFoundError:
        print(Fore.RED + "Nmap is not installed or not found in PATH")
        sys.exit(1)
    except KeyboardInterrupt:
        print(Fore.RED + "\nScan interrupted by user")
        sys.exit(1)


def menu():
    """Display main menu options"""
    print(Fore.YELLOW + Style.BRIGHT + """
Nmap Scan Automation Menu
=========================
1) Quick Scan (nmap -T4 -F)
2) Intense Scan (nmap -T4 -A -v)
3) UDP Scan (nmap -sU --top-ports 100)
4) TCP SYN Scan (nmap -sS)
5) Service Version Detection (nmap -sV)
6) OS Detection (nmap -O)
7) Firewall Detection Scan (nmap -sA)
8) Firewall Evasion Scan (advanced techniques)
9) Complete Scan (combines multiple scans)
10) Custom Scan
11) Exit
""")


def firewall_evasion_scan(target):
    """Perform advanced firewall evasion techniques"""
    base_args = [
        "-sS",  # TCP SYN scan
        "-f",  # Fragment packets
        "--mtu",
        "24",  # More realistic MTU size
        "-T2",  # Slow timing
        "--data-length",
        "50",  # Add random data
        "--badsum",  # Send invalid checksums
    ]
    run_nmap(base_args, target, "Advanced Firewall Evasion Scan")


def complete_scan(target):
    """Run comprehensive sequence of scans"""
    # Ask once for the whole batch, not once per sub-scan below.
    decoy_args = get_decoys()
    spoof_args = get_spoof_options()

    scans = [
        (["-T4", "-F"], "Quick Scan"),
        (["-sS", "-p-", "--open"], "TCP SYN Scan (All Ports)"),
        (["-sU", "--top-ports", "100"], "UDP Scan (Top 100 Ports)"),
        (["-sV", "-O", "--version-all"], "Service/OS Detection"),
        (["-sA"], "Firewall Detection"),
        (["--script", "vuln"], "Vulnerability Scan"),
    ]

    for args, desc in scans:
        run_nmap(args, target, desc, decoy_args=decoy_args, spoof_args=spoof_args)


def custom_scan(target):
    """Run user-defined nmap command"""
    print(Fore.MAGENTA + "Enter custom Nmap options (e.g. -sS -sV -p 80,443)")
    user_input = input(Fore.CYAN + "Options: ").strip()

    if not user_input:
        print(Fore.RED + "No options provided")
        return

    args = user_input.split()
    run_nmap(args, target, "Custom Scan")


def main():
    """Main program loop"""
    print(Fore.CYAN + Style.BRIGHT + "\nNmap Automation Tool - Advanced Evasion Techniques")
    print(Fore.YELLOW + "=" * 60)
    print(Fore.MAGENTA + "Note: Spoofing requires specifying a network interface")

    # Check if running as root
    if os.geteuid() != 0:
        print(Fore.RED + "Warning: Running without root privileges. Some scans may fail.")
        print(Fore.RED + "Consider running with 'sudo' for full functionality.\n")

    while True:
        menu()
        choice = input(Fore.MAGENTA + "Choose a scan type (1-11): ").strip()

        if choice == "11":
            print(Fore.CYAN + "Exiting...")
            break

        if choice not in [str(x) for x in range(1, 12)]:
            print(Fore.RED + "Invalid choice. Select 1-11")
            continue

        target = input(Fore.MAGENTA + "Enter target IP/hostname: ").strip()
        if not validate_target(target):
            print(Fore.RED + "Invalid target address")
            continue

        if choice == "1":
            run_nmap(["-T4", "-F"], target, "Quick Scan")
        elif choice == "2":
            run_nmap(["-T4", "-A", "-v"], target, "Intense Scan")
        elif choice == "3":
            run_nmap(["-sU", "--top-ports", "100"], target, "UDP Scan")
        elif choice == "4":
            run_nmap(["-sS"], target, "TCP SYN Scan")
        elif choice == "5":
            run_nmap(["-sV"], target, "Service Detection")
        elif choice == "6":
            run_nmap(["-O"], target, "OS Detection")
        elif choice == "7":
            run_nmap(["-sA"], target, "Firewall Detection")
        elif choice == "8":
            firewall_evasion_scan(target)
        elif choice == "9":
            complete_scan(target)
        elif choice == "10":
            custom_scan(target)


if __name__ == "__main__":
    main()
