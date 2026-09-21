#!/usr/bin/env python3
import argparse
import random
import sys
import threading
import time
import warnings
from datetime import datetime

warnings.filterwarnings("ignore", category=DeprecationWarning)
warnings.filterwarnings("ignore", category=UserWarning)

try:
    from scapy.all import ICMP, IP, TCP, UDP, send, sr1
    from scapy.all import fragment as scapy_fragment
except ImportError:
    print("Error: Scapy library not found. Please install it with: pip install scapy")
    sys.exit(1)


def banner():
    print("=" * 50)
    print("           PORT SCANNER WITH SCAPY")
    print("=" * 50)
    print()


def detect_firewall(host, open_ports, closed_ports):
    """Detect potential firewall presence based on scan results"""
    firewall_indicators = []

    # Check for consistent filtered responses
    filtered_count = len([p for p in closed_ports if closed_ports[p] == "Filtered"])
    total_ports = len(open_ports) + len(closed_ports)

    if filtered_count / total_ports > 0.7:
        firewall_indicators.append("High percentage of filtered ports")

    # Check for sequential open ports (unusual pattern)
    if len(open_ports) > 1:
        sorted_ports = sorted(open_ports.keys())
        sequential = sum(1 for i in range(len(sorted_ports)-1) if sorted_ports[i+1] - sorted_ports[i] == 1)
        if sequential / len(sorted_ports) > 0.8:
            firewall_indicators.append("Unusual sequential port pattern")

    return firewall_indicators


def firewall_evasion_delay():
    """Add random delay to evade rate limiting"""
    delay = random.uniform(0.1, 0.5)
    time.sleep(delay)


def fragment_packet(packet, fragment_size=8):
    """Fragment IP packet to evade firewalls"""
    try:
        fragments = scapy_fragment(packet, fragsize=fragment_size)
        return fragments
    except Exception:
        return [packet]


def decoy_scan(host, port, scan_type, decoy_ips=None):
    """Perform scan with decoy IPs to mask real source"""
    if decoy_ips is None:
        # Generate random decoy IPs
        decoy_ips = [f"{random.randint(1, 254)}.{random.randint(1, 254)}.{random.randint(1, 254)}.{random.randint(1, 254)}"
                    for _ in range(3)]

    # Perform decoy scans (won't wait for responses)
    for decoy_ip in decoy_ips:
        try:
            if scan_type == "1":
                send(IP(src=decoy_ip, dst=host)/TCP(dport=port, flags="S"), verbose=0)
            elif scan_type == "6":
                send(IP(src=decoy_ip, dst=host)/UDP(dport=port), verbose=0)
        except Exception:
            pass

    # Perform actual scan
    firewall_evasion_delay()
    return scan_port(host, port, scan_type)


def source_port_scan(host, port, scan_type, source_port=53):
    """Scan using specific source port (often allowed through firewalls)"""
    try:
        if scan_type == "1":
            response = sr1(IP(dst=host)/TCP(sport=source_port, dport=port, flags="S"), timeout=1, verbose=0)
        elif scan_type == "6":
            response = sr1(IP(dst=host)/UDP(sport=source_port, dport=port), timeout=1, verbose=0)
        else:
            return scan_port(host, port, scan_type)

        if response is None:
            return "Filtered"
        elif response.haslayer(TCP):
            if response[TCP].flags == 18:
                return "Open"
            elif response[TCP].flags == 4:
                return "Closed"
        elif response.haslayer(UDP):
            return "Open"
        elif response.haslayer(ICMP):
            if response[ICMP].type == 3 and response[ICMP].code == 3:
                return "Closed"
        return "Filtered"
    except Exception:
        return scan_port(host, port, scan_type)


def timing_evasion_scan(host, port, scan_type, timing_level=3):
    """Perform scan with timing evasion"""
    timing_delays = {
        1: 15,      # Paranoid
        2: 5,       # Sneaky
        3: 1,       # Polite
        4: 0.5,     # Normal
        5: 0.1      # Aggressive
    }

    delay = timing_delays.get(timing_level, 1)
    time.sleep(delay)

    return scan_port(host, port, scan_type)


def tcp_syn_scan(host, port):
    """TCP SYN Scan"""
    response = sr1(IP(dst=host)/TCP(dport=port, flags="S"), timeout=1, verbose=0)
    if response is None:
        return "Filtered"
    elif response.haslayer(TCP):
        if response[TCP].flags == 18:  # SYN-ACK
            return "Open"
        elif response[TCP].flags == 4:  # RST
            return "Closed"
    return "Filtered"


def tcp_connect_scan(host, port):
    """TCP Connect Scan"""
    response = sr1(IP(dst=host)/TCP(dport=port, flags="S"), timeout=1, verbose=0)
    if response is None:
        return "Filtered"
    elif response.haslayer(TCP):
        if response[TCP].flags == 18:  # SYN-ACK
            # Send ACK to complete handshake
            sr1(IP(dst=host)/TCP(dport=port, flags="A"), timeout=1, verbose=0)
            return "Open"
        elif response[TCP].flags == 4:  # RST
            return "Closed"
    return "Filtered"


def tcp_fin_scan(host, port):
    """TCP FIN Scan"""
    response = sr1(IP(dst=host)/TCP(dport=port, flags="F"), timeout=1, verbose=0)
    if response is None:
        return "Open|Filtered"
    elif response.haslayer(TCP):
        if response[TCP].flags == 4:  # RST
            return "Closed"
    return "Open|Filtered"


def tcp_xmas_scan(host, port):
    """TCP XMAS Scan"""
    response = sr1(IP(dst=host)/TCP(dport=port, flags="FPU"), timeout=1, verbose=0)
    if response is None:
        return "Open|Filtered"
    elif response.haslayer(TCP):
        if response[TCP].flags == 4:  # RST
            return "Closed"
    return "Open|Filtered"


def tcp_null_scan(host, port):
    """TCP NULL Scan"""
    response = sr1(IP(dst=host)/TCP(dport=port, flags=""), timeout=1, verbose=0)
    if response is None:
        return "Open|Filtered"
    elif response.haslayer(TCP):
        if response[TCP].flags == 4:  # RST
            return "Closed"
    return "Open|Filtered"


def udp_scan(host, port):
    """UDP Scan"""
    response = sr1(IP(dst=host)/UDP(dport=port), timeout=1, verbose=0)
    if response is None:
        return "Open|Filtered"
    elif response.haslayer(ICMP):
        if response[ICMP].type == 3 and response[ICMP].code == 3:
            return "Closed"
    elif response.haslayer(UDP):
        return "Open"
    return "Open|Filtered"


def scan_port(host, port, scan_type):
    """Scan a single port"""
    if scan_type == "1":
        return tcp_syn_scan(host, port)
    elif scan_type == "2":
        return tcp_connect_scan(host, port)
    elif scan_type == "3":
        return tcp_fin_scan(host, port)
    elif scan_type == "4":
        return tcp_xmas_scan(host, port)
    elif scan_type == "5":
        return tcp_null_scan(host, port)
    elif scan_type == "6":
        return udp_scan(host, port)
    else:
        return "Invalid scan type"


def scan_ports(host, ports, scan_type, threads=50):
    """Scan multiple ports with threading"""
    print(f"Starting scan on {host}")
    print(f"Scan started at: {datetime.now()}")
    print("-" * 50)

    def thread_scan(port):
        result = scan_port(host, port, scan_type)
        if result == "Open" or "Open" in result:
            print(f"Port {port}: {result}")

    # Create and start threads
    thread_list = []
    for port in ports:
        t = threading.Thread(target=thread_scan, args=(port,))
        thread_list.append(t)
        t.start()

        # Limit concurrent threads
        if len(thread_list) >= threads:
            for thread in thread_list:
                thread.join()
            thread_list = []

    # Wait for remaining threads
    for thread in thread_list:
        thread.join()

    print("-" * 50)
    print(f"Scan completed at: {datetime.now()}")


def display_menu():
    """Display scan type menu"""
    print("\nSelect Scan Type:")
    print("1. TCP SYN Scan (Stealth)")
    print("2. TCP Connect Scan")
    print("3. TCP FIN Scan")
    print("4. TCP XMAS Scan")
    print("5. TCP NULL Scan")
    print("6. UDP Scan")
    print("7. Exit")
    print()


def parse_ports(port_range):
    """Parse port range string into list of ports"""
    ports = []
    for part in port_range.split(','):
        if '-' in part:
            start, end = map(int, part.split('-'))
            ports.extend(range(start, end + 1))
        else:
            ports.append(int(part))
    return ports


def main():
    banner()

    if len(sys.argv) > 1:
        # Command line mode
        parser = argparse.ArgumentParser(description='Port Scanner with Scapy')
        parser.add_argument('host', help='Target host to scan')
        parser.add_argument('-p', '--ports', default='1-1000', help='Port range (e.g., 1-1000 or 80,443,8080)')
        parser.add_argument('-t', '--type', default='1', choices=['1', '2', '3', '4', '5', '6'],
                          help='Scan type (1-6)')
        parser.add_argument('--threads', default=50, type=int, help='Number of threads')

        args = parser.parse_args()

        try:
            ports = parse_ports(args.ports)
            scan_ports(args.host, ports, args.type, args.threads)
        except ValueError:
            print("Error: Invalid port range format")
        except KeyboardInterrupt:
            print("\nScan interrupted by user")
        except Exception as e:
            print(f"Error: {e}")
    else:
        # Interactive mode
        while True:
            display_menu()

            choice = input("Enter your choice (1-7): ").strip()

            if choice == "7":
                print("Goodbye!")
                break

            if choice not in ["1", "2", "3", "4", "5", "6"]:
                print("Invalid choice. Please try again.")
                continue

            host = input("Enter target host (IP or domain): ").strip()
            if not host:
                print("Host cannot be empty!")
                continue

            port_input = input("Enter port range (e.g., 1-1000 or 80,443,8080) [default: 1-1000]: ").strip()
            if not port_input:
                port_input = "1-1000"

            threads = input("Enter number of threads [default: 50]: ").strip()
            if not threads:
                threads = 50
            else:
                try:
                    threads = int(threads)
                except ValueError:
                    threads = 50

            try:
                ports = parse_ports(port_input)
                scan_ports(host, ports, choice, threads)
            except ValueError:
                print("Error: Invalid port range format")
            except KeyboardInterrupt:
                print("\nScan interrupted by user")
            except Exception as e:
                print(f"Error: {e}")

            input("\nPress Enter to continue...")


if __name__ == "__main__":
    main()
