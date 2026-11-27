# VM table
# VM_CONFIG: box, size, VLAN and host number for every VM.
# Loaded in order by the Vagrantfile (require_relative); see vagrant/README.md.

# ==============================================================================
# DATA-DRIVEN VM CONFIGURATION
# ==============================================================================
VM_CONFIG = {
  'opnsense' => {
    box: PROVIDER == :libvirt ? 'harmonnine/opnsense-kvm' : 'harmonnine/opnsense',
    box_version: 'latest', memory: 2048, cpus: 2, disk_size: 20,
    hostname: 'opnsense', guest: :linux, vlan: 10, host_number: 1, autostart: true,
    ssh_username: 'root', ssh_password: 'opnsense',
    health_check: { type: :http, port: 80, path: '/', timeout: 300 }
  },
  'DC01' => {
    box: 'peru/windows-server-2022-standard-x64-eval', box_version: 'latest', memory: 4096, cpus: 2, disk_size: 60,
    hostname: 'dc01', guest: :windows, vlan: 10, host_number: 21, autostart: true, primary: true,
    health_check: { type: :winrm, port: 5985, timeout: 1200, marker: 'C:\\DC-FINAL.txt' }
  },
  'kali' => {
    # Defaults to Kali Linux; override with KALI_BOX / KALI_BOX_VERSION
    # to use Parrot Security or another Debian-based box instead, e.g.:
    #   KALI_BOX=ParrotSec/Parrot-security-7.3-libvirt-amd64 KALI_BOX_VERSION=7.3 vagrant up
    box: ENV.fetch('KALI_BOX', 'kalilinux/rolling'), box_version: ENV.fetch('KALI_BOX_VERSION', '2026.1.0'), memory: 4096, cpus: 2, disk_size: 80,
    hostname: 'kali.lab.local', guest: :linux, vlan: 99, host_number: 10, autostart: true, nat_ip: '192.168.100.180',
    health_check: { type: :ssh, port: 22, timeout: 300 }
  },
  'CA01-ESC' => {
    box: 'peru/windows-server-2022-standard-x64-eval', box_version: 'latest', memory: 4096, cpus: 2, disk_size: 60,
    hostname: 'ca01-esc', guest: :windows, vlan: 10, host_number: 25, autostart: true
  },
  'DB01' => {
    box: 'peru/windows-server-2019-standard-x64-eval', box_version: 'latest', memory: 4096, cpus: 2, disk_size: 80,
    hostname: 'db01', guest: :windows, vlan: 10, host_number: 23, autostart: true
  },
  'WIN10' => {
    box: 'peru/windows-10-enterprise-x64-eval', box_version: 'latest', memory: 2048, cpus: 2, disk_size: 40,
    hostname: 'win10', guest: :windows, vlan: 20, host_number: 30, autostart: true
  },
  'linux01' => {
    box: 'generic/ubuntu2204', box_version: 'latest', memory: 1024, cpus: 1, disk_size: 20,
    hostname: 'linux01', guest: :linux, vlan: 30, host_number: 72, autostart: true
  },
  'print01' => {
    box: 'peru/windows-server-2019-standard-x64-eval', box_version: 'latest', memory: 2048, cpus: 2, disk_size: 40,
    hostname: 'print01', guest: :windows, vlan: 30, host_number: 73, autostart: true
  },
  'llm01' => {
    box: 'generic/ubuntu2204', box_version: 'latest', memory: 8192, cpus: 4, disk_size: 100,
    hostname: 'llm01', guest: :linux, vlan: 30, host_number: 60, autostart: true
  },
  'cloud-pentest' => {
    box: 'generic/ubuntu2204', box_version: 'latest', memory: 2048, cpus: 2, disk_size: 40,
    hostname: 'cloud-pentest', guest: :linux, vlan: 30, host_number: 80, autostart: true
  },
  'metasploitable2' => {
    box: 'deargle/metasploitable2', box_version: '0.1.0', memory: 512, cpus: 1, disk_size: 10,
    hostname: 'metasploitable2', guest: :linux, vlan: 40, host_number: 12, autostart: true,
    ssh_username: 'msfadmin', ssh_password: 'msfadmin'
  },
  'juice-shop' => {
    box: 'ubuntu/jammy64', box_version: '20241007.0.0', memory: 2048, cpus: 2, disk_size: 20,
    hostname: 'juice-shop', guest: :linux, vlan: 40, host_number: 15, autostart: true
  }
}
