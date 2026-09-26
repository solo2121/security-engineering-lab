# Security Tooling

This directory contains standalone security scripts and experiments for authorized lab use. The tools support reconnaissance, network analysis, detection engineering, wireless lab practice, and intentionally vulnerable security-testing workflows.

Use these tools only on systems and lab networks you own or are explicitly authorized to test. For project-wide boundaries, read [`../../docs/security-scope.md`](../../docs/security-scope.md).

---

## Directory Map

| Directory | Contents |
|-----------|----------|
| [`audit/`](audit/) | Cisco switch audit tooling (SSH/Telnet credential checks, reporting) |
| [`network/`](network/) | Firewall scan wrapper, Scapy port scanner, tcpdump wrapper, and Ettercap menu |
| [`exploitation/`](exploitation/) | Educational exploit script covering SQLi, XSS, directory bruteforce, and SSRF testing |
| [`reconnaissance/`](reconnaissance/) | Amass, nmap, and port-scanning helpers |
| [`wireless/`](wireless/) | Wireless lab tooling, including evil-twin experimentation |

---

## Portfolio Highlights

- Python and Bash tooling for practical security operations.
- Clear separation between reconnaissance, detection, testing, and wireless experiments.
- Lab-oriented scripts that support controlled attack-and-defense learning.
- Integration with the larger lab environments under [`../../labs/security/`](../../labs/security/).

---

## Example Usage

Run scripts from their own directories so relative paths and output files stay predictable:

```bash
cd security/reconnaissance
python3 port-scanner.py
```

```bash
cd security/network
./firewall-scan.sh
```

Check each script before execution and confirm the target is within your authorized lab scope.

---

## Safety Rules

- Do not scan public IP ranges without written authorization.
- Do not run credential, exploit, wireless, or packet-capture tooling on networks you do not control.
- Keep testing inside isolated VMs or lab VLANs.
- Treat generated output as sensitive until reviewed.
- Prefer defense, validation, and remediation notes alongside offensive findings.

---

## Related Labs

- [`../../labs/security/active-directory/base/`](../../labs/security/active-directory/base/)
- [`../../labs/security/active-directory/vlan-segmented/`](../../labs/security/active-directory/vlan-segmented/)
- [`../../docs/security-scope.md`](../../docs/security-scope.md)
