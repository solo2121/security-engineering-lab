# Ansible Automation — Lab Guide

A practical guide for using Ansible against the Linux nodes in the DevOps lab. It covers inventory setup, ad-hoc commands, playbooks, roles, and hardening automation grounded in the actual lab VM topology.

**Lab nodes available for Ansible:**

| Host | IP (typical) | OS | Role |
|------|--------------|----|------|
| node1 | 192.168.121.30 | Ubuntu 24.04 | Ansible managed node |
| node2 | 192.168.121.31 | Ubuntu 24.04 | Ansible managed node |
| ubuntu-lab | 192.168.121.20 | Ubuntu 24.04 | Linux practice node |
| rocky-lab | 192.168.121.21 | Rocky Linux 10 | Linux practice node |
| alma-lab | 192.168.121.22 | AlmaLinux 10 | Linux practice node |
| suse-lab | 192.168.121.23 | openSUSE Leap 15.6 | Linux practice node |

SSH keys are automatically distributed from `devops-1` to all nodes during provisioning.

***

## Table of Contents

1. [Setup and Prerequisites](#1-setup-and-prerequisites)
2. [Inventory](#2-inventory)
3. [Configuration](#3-configuration)
4. [Ad-Hoc Commands](#4-ad-hoc-commands)
5. [Playbook Fundamentals](#5-playbook-fundamentals)
6. [Variables and Facts](#6-variables-and-facts)
7. [Templates with Jinja2](#7-templates-with-jinja2)
8. [Handlers](#8-handlers)
9. [Roles](#9-roles)
10. [Hardening Playbooks](#10-hardening-playbooks)
11. [Vault — Encrypting Secrets](#11-vault--encrypting-secrets)
12. [Ansible Galaxy](#12-ansible-galaxy)
13. [Testing with Molecule](#13-testing-with-molecule)
14. [Troubleshooting](#14-troubleshooting)

***

## 1. Setup and Prerequisites

### Install Ansible on devops-1

```bash
# SSH into the control node
vagrant ssh devops-1

# Install Ansible
sudo apt update
sudo apt install -y ansible python3-pip

# Verify
ansible --version

# Install useful extras
pip3 install ansible-lint molecule molecule-plugins[docker]
```

### Verify SSH Keys Are in Place

The Vagrantfile distributes `devops-1`'s SSH key to all nodes at boot. Verify:

```bash
# From devops-1
ssh vagrant@192.168.121.30 "hostname"   # node1
ssh vagrant@192.168.121.31 "hostname"   # node2
ssh vagrant@192.168.121.20 "hostname"   # ubuntu-lab
ssh vagrant@192.168.121.21 "hostname"   # rocky-lab
ssh vagrant@192.168.121.22 "hostname"   # alma-lab
ssh vagrant@192.168.121.23 "hostname"   # suse-lab
```

All should respond without a password prompt. If not:

```bash
# Copy key manually
ssh-copy-id -i ~/.ssh/id_rsa.pub vagrant@192.168.121.30
ssh-copy-id -i ~/.ssh/id_rsa.pub vagrant@192.168.121.31
```

***

## 2. Inventory

The inventory tells Ansible which hosts exist and how to group them.

### Static Inventory — INI Format

Create `/etc/ansible/hosts` or a local `inventory/hosts.ini`:

```ini
# inventory/hosts.ini

[managed_nodes]
node1 ansible_host=192.168.121.30
node2 ansible_host=192.168.121.31

[ubuntu_nodes]
ubuntu-lab ansible_host=192.168.121.20

[redhat_nodes]
rocky-lab  ansible_host=192.168.121.21
alma-lab   ansible_host=192.168.121.22

[suse_nodes]
suse-lab   ansible_host=192.168.121.23

[linux_labs:children]
ubuntu_nodes
redhat_nodes
suse_nodes

[all_lab_nodes:children]
managed_nodes
linux_labs

[all_lab_nodes:vars]
ansible_user=vagrant
ansible_ssh_private_key_file=/home/vagrant/.ssh/id_rsa
ansible_become=true
ansible_become_method=sudo
```

### Static Inventory — YAML Format

```yaml
# inventory/hosts.yaml
all:
  children:
    managed_nodes:
      hosts:
        node1:
          ansible_host: 192.168.121.30
        node2:
          ansible_host: 192.168.121.31
    linux_labs:
      children:
        ubuntu_nodes:
          hosts:
            ubuntu-lab:
              ansible_host: 192.168.121.20
        redhat_nodes:
          hosts:
            rocky-lab:
              ansible_host: 192.168.121.21
            alma-lab:
              ansible_host: 192.168.121.22
        suse_nodes:
          hosts:
            suse-lab:
              ansible_host: 192.168.121.23
  vars:
    ansible_user: vagrant
    ansible_ssh_private_key_file: /home/vagrant/.ssh/id_rsa
    ansible_become: true
    ansible_become_method: sudo
```

### Verify the Inventory

```bash
# List all hosts
ansible-inventory -i inventory/hosts.ini --list

# Graph the group hierarchy
ansible-inventory -i inventory/hosts.ini --graph

# Ping all hosts
ansible all -i inventory/hosts.ini -m ping
```

Expected output:

```text
node1 | SUCCESS => { "ping": "pong" }
node2 | SUCCESS => { "ping": "pong" }
ubuntu-lab | SUCCESS => { "ping": "pong" }
rocky-lab | SUCCESS => { "ping": "pong" }
alma-lab | SUCCESS => { "ping": "pong" }
suse-lab | SUCCESS => { "ping": "pong" }
```

***

## 3. Configuration

Create `ansible.cfg` in your project root. Ansible uses the project-local config before the system-wide configuration.

```ini
# ansible.cfg
[defaults]
inventory = inventory/hosts.ini
remote_user = vagrant
private_key_file = /home/vagrant/.ssh/id_rsa
host_key_checking = False
forks = 10
timeout = 30
stdout_callback = yaml
callbacks_enabled = timer, profile_tasks

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
```

With this in place, you can drop the `-i inventory/hosts.ini` flag from most commands.

***

## 4. Ad-Hoc Commands

Ad-hoc commands run a single module without writing a playbook. They are useful for quick checks and one-off tasks.

### Syntax

```bash
ansible <pattern> -m <module> -a "<arguments>"
```

### Connectivity and Facts

```bash
# Ping all hosts
ansible all -m ping

# Ping a specific group
ansible managed_nodes -m ping

# Gather all facts about a host
ansible node1 -m setup

# Filter facts
ansible node1 -m setup -a "filter=ansible_os_family"
ansible node1 -m setup -a "filter=ansible_distribution*"
ansible node1 -m setup -a "filter=ansible_memory_mb"

# Run a raw command (no Python required on target)
ansible all -m raw -a "uname -r"
```

### System Information

```bash
# Check uptime on all nodes
ansible all -m command -a "uptime"

# Check disk usage
ansible all -m command -a "df -h"

# Check memory
ansible all -m command -a "free -m"

# Check running services
ansible managed_nodes -m command -a "systemctl is-active sshd"

# Get OS release info
ansible linux_labs -m command -a "cat /etc/os-release"
```

### Package Management

```bash
# Install a package on Ubuntu nodes
ansible ubuntu_nodes -m apt -a "name=htop state=present update_cache=yes"

# Install on RedHat nodes
ansible redhat_nodes -m dnf -a "name=htop state=present"

# Install on SUSE nodes
ansible suse_nodes -m zypper -a "name=htop state=present"

# Remove a package
ansible ubuntu_nodes -m apt -a "name=telnet state=absent"

# Update all packages (Ubuntu)
ansible ubuntu_nodes -m apt -a "upgrade=dist update_cache=yes"
```

### File Operations

```bash
# Create a directory
ansible all -m file -a "path=/opt/lab state=directory mode=0755"

# Copy a file to all nodes
ansible all -m copy -a "src=/tmp/test.txt dest=/tmp/test.txt mode=0644"

# Create a file with content
ansible all -m copy -a "content='hello from ansible' dest=/tmp/hello.txt"

# Remove a file
ansible all -m file -a "path=/tmp/hello.txt state=absent"

# Check file stats
ansible all -m stat -a "path=/etc/passwd"
```

### User Management

```bash
# Create a user
ansible all -m user -a "name=labuser state=present shell=/bin/bash"

# Add user to a group
ansible all -m user -a "name=labuser groups=sudo append=yes"

# Set a password (use vault in production)
ansible all -m user -a "name=labuser password={{ 'password123' | password_hash('sha512') }}"

# Remove a user
ansible all -m user -a "name=labuser state=absent remove=yes"
```

### Service Management

```bash
# Start and enable a service
ansible all -m service -a "name=sshd state=started enabled=yes"

# Restart a service
ansible managed_nodes -m service -a "name=cron state=restarted"

# Stop a service
ansible all -m service -a "name=cups state=stopped enabled=no"
```

***

## 5. Playbook Fundamentals

Playbooks are YAML files that define a sequence of tasks to run against hosts.

### Project Structure

```text
ansible-lab/
├── ansible.cfg
├── inventory/
│   └── hosts.ini
├── playbooks/
│   ├── site.yml          # Master playbook
│   ├── hardening.yml
│   ├── packages.yml
│   └── users.yml
├── roles/
│   ├── common/
│   ├── hardening/
│   └── monitoring/
├── templates/
│   └── sshd_config.j2
├── files/
│   └── motd
└── vars/
    └── main.yml
```

### Basic Playbook Structure

```yaml
# playbooks/packages.yml
---
- name: Install common packages on all lab nodes
  hosts: all_lab_nodes
  become: true

  vars:
    common_packages_debian:
      - curl
      - wget
      - git
      - vim
      - htop
      - tree
      - tmux
      - net-tools
      - nmap
      - tcpdump

    common_packages_redhat:
      - curl
      - wget
      - git
      - vim-enhanced
      - htop
      - tree
      - tmux
      - net-tools
      - nmap
      - tcpdump

  tasks:
    - name: Install packages on Debian/Ubuntu
      ansible.builtin.apt:
        name: "{{ common_packages_debian }}"
        state: present
        update_cache: true
      when: ansible_os_family == "Debian"

    - name: Install packages on RedHat/Rocky/Alma
      ansible.builtin.dnf:
        name: "{{ common_packages_redhat }}"
        state: present
      when: ansible_os_family == "RedHat"

    - name: Install packages on SUSE
      community.general.zypper:
        name: "{{ common_packages_redhat }}"
        state: present
      when: ansible_os_family == "Suse"
```

### Running Playbooks

```bash
# Syntax check before running
ansible-playbook playbooks/packages.yml --syntax-check

# Dry run (check mode — no changes made)
ansible-playbook playbooks/packages.yml --check

# Show what would change with diff
ansible-playbook playbooks/packages.yml --check --diff

# Run the playbook
ansible-playbook playbooks/packages.yml

# Run only on a specific host
ansible-playbook playbooks/packages.yml --limit node1

# Run only on a specific group
ansible-playbook playbooks/packages.yml --limit ubuntu_nodes

# Run specific tags
ansible-playbook playbooks/packages.yml --tags "install"

# Skip specific tags
ansible-playbook playbooks/packages.yml --skip-tags "cleanup"

# Increase verbosity
ansible-playbook playbooks/packages.yml -v    # basic
ansible-playbook playbooks/packages.yml -vvv  # full debug
```

### Task Control

```yaml
tasks:
  - name: Only run on Ubuntu
    ansible.builtin.apt:
      name: ufw
      state: present
    when: ansible_distribution == "Ubuntu"

  - name: Run on multiple conditions
    ansible.builtin.command: echo "hello"
    when:
      - ansible_os_family == "Debian"
      - ansible_memtotal_mb >= 512

  - name: Loop over a list
    ansible.builtin.user:
      name: "{{ item }}"
      state: present
    loop:
      - alice
      - bob
      - charlie

  - name: Loop over a dict
    ansible.builtin.debug:
      msg: "User {{ item.name }} has shell {{ item.shell }}"
    loop:
      - { name: alice, shell: /bin/bash }
      - { name: bob, shell: /bin/sh }

  - name: Ignore errors on this task
    ansible.builtin.command: /usr/bin/might-fail
    ignore_errors: true

  - name: Register output for later use
    ansible.builtin.command: hostname
    register: hostname_output

  - name: Use the registered output
    ansible.builtin.debug:
      msg: "Hostname is {{ hostname_output.stdout }}"

  - name: Run only when a condition from a previous task is met
    ansible.builtin.debug:
      msg: "This is node1"
    when: hostname_output.stdout == "node1"
```

***

## 6. Variables and Facts

### Variable Precedence

```text
role defaults → inventory vars → playbook vars → task vars → extra vars (-e)
```

### Defining Variables

```yaml
# In a playbook
vars:
  ntp_server: "172.28.1.1"
  max_connections: 100
  allowed_users:
    - vagrant
    - alice

# In a separate vars file
vars_files:
  - vars/main.yml
  - vars/secrets.yml

# On the command line (highest priority)
ansible-playbook site.yml -e "ntp_server=1.1.1.1"
ansible-playbook site.yml -e "@vars/override.yml"
```

### Group and Host Variables

```text
inventory/
├── group_vars/
│   ├── all.yml              # Applies to all hosts
│   ├── managed_nodes.yml    # Applies to managed_nodes group
│   └── redhat_nodes.yml     # Applies to redhat_nodes group
└── host_vars/
    ├── node1.yml            # Applies only to node1
    └── rocky-lab.yml        # Applies only to rocky-lab
```

```yaml
# inventory/group_vars/all.yml
ntp_servers:
  - 0.pool.ntp.org
  - 1.pool.ntp.org
timezone: America/New_York
admin_email: admin@lab.local

# inventory/group_vars/redhat_nodes.yml
selinux_state: enforcing
firewall_service: firewalld

# inventory/host_vars/node1.yml
node_role: primary
node_extra_disk: /dev/vdb
```

### Using Facts

```yaml
tasks:
  - name: Show OS family
    ansible.builtin.debug:
      msg: "OS: {{ ansible_distribution }} {{ ansible_distribution_version }}"

  - name: Show IP address
    ansible.builtin.debug:
      msg: "IP: {{ ansible_default_ipv4.address }}"

  - name: Show memory
    ansible.builtin.debug:
      msg: "RAM: {{ ansible_memtotal_mb }} MB"

  - name: Set a custom fact
    ansible.builtin.set_fact:
      lab_environment: "dev"
      build_time: "{{ ansible_date_time.iso8601 }}"
```

***

## 7. Templates with Jinja2

Templates generate configuration files dynamically using host-specific values.

### MOTD Template

```jinja2
{# templates/motd.j2 #}
================================================================================
  Host     : {{ ansible_hostname }}
  OS       : {{ ansible_distribution }} {{ ansible_distribution_version }}
  IP       : {{ ansible_default_ipv4.address }}
  Memory   : {{ ansible_memtotal_mb }} MB
  CPU      : {{ ansible_processor_vcpus }} vCPUs
  Managed  : Ansible {{ ansible_version.full }}
================================================================================
WARNING: This system is for authorized lab use only.
================================================================================
```

```yaml
- name: Deploy MOTD
  ansible.builtin.template:
    src: templates/motd.j2
    dest: /etc/motd
    owner: root
    group: root
    mode: '0644'
```

### SSH Config Template

```jinja2
{# templates/sshd_config.j2 #}
Port {{ ssh_port | default(22) }}
Protocol 2
PermitRootLogin {{ ssh_permit_root_login | default('no') }}
PasswordAuthentication {{ ssh_password_auth | default('no') }}
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
MaxAuthTries {{ ssh_max_auth_tries | default(3) }}
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PrintLastLog yes
Banner /etc/motd

{% if ssh_allowed_users is defined %}
AllowUsers {{ ssh_allowed_users | join(' ') }}
{% endif %}
```

```yaml
- name: Deploy SSH config
  ansible.builtin.template:
    src: templates/sshd_config.j2
    dest: /etc/ssh/sshd_config
    owner: root
    group: root
    mode: '0600'
    validate: /usr/sbin/sshd -t -f %s
  notify: Restart sshd
```

### NTP Config Template

```jinja2
{# templates/chrony.conf.j2 #}
{% for server in ntp_servers %}
server {{ server }} iburst
{% endfor %}
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
```

***

## 8. Handlers

Handlers run only when notified by a task that made a change. They are commonly used for service restarts.

```yaml
---
- name: Configure and harden SSH
  hosts: all_lab_nodes
  become: true

  handlers:
    - name: Restart sshd
      ansible.builtin.service:
        name: "{{ 'ssh' if ansible_os_family == 'Debian' else 'sshd' }}"
        state: restarted

    - name: Reload firewall
      ansible.builtin.service:
        name: ufw
        state: reloaded

    - name: Apply sysctl
      ansible.builtin.command: sysctl --system

  tasks:
    - name: Deploy sshd_config
      ansible.builtin.template:
        src: templates/sshd_config.j2
        dest: /etc/ssh/sshd_config
        validate: /usr/sbin/sshd -t -f %s
      notify: Restart sshd

    - name: Deploy sysctl hardening
      ansible.builtin.template:
        src: templates/sysctl-hardening.j2
        dest: /etc/sysctl.d/99-hardening.conf
      notify: Apply sysctl
```

***

## 9. Roles

Roles organize playbooks into reusable, shareable units with a standardized directory structure.

### Role Structure

```text
roles/
└── hardening/
    ├── defaults/
    │   └── main.yml
    ├── vars/
    │   └── main.yml
    ├── tasks/
    │   ├── main.yml
    │   ├── ssh.yml
    │   ├── users.yml
    │   ├── packages.yml
    │   └── sysctl.yml
    ├── handlers/
    │   └── main.yml
    ├── templates/
    │   ├── sshd_config.j2
    │   └── sysctl.j2
    ├── files/
    │   └── sudoers_lab
    ├── meta/
    │   └── main.yml
    └── README.md
```

### Create a Role

```bash
# Create the role structure automatically
ansible-galaxy role init roles/hardening
ansible-galaxy role init roles/common
ansible-galaxy role init roles/monitoring
```

### Common Role — tasks/main.yml

```yaml
# roles/common/tasks/main.yml
---
- name: Import package tasks
  ansible.builtin.import_tasks: packages.yml

- name: Import user tasks
  ansible.builtin.import_tasks: users.yml

- name: Import motd tasks
  ansible.builtin.import_tasks: motd.yml
```

```yaml
# roles/common/tasks/packages.yml
---
- name: Install common packages (Debian)
  ansible.builtin.apt:
    name: "{{ common_packages }}"
    state: present
    update_cache: true
  when: ansible_os_family == "Debian"

- name: Install common packages (RedHat)
  ansible.builtin.dnf:
    name: "{{ common_packages }}"
    state: present
  when: ansible_os_family == "RedHat"
```

```yaml
# roles/common/defaults/main.yml
---
common_packages:
  - curl
  - wget
  - git
  - vim
  - htop
  - tree
  - tmux
  - net-tools
```

### Using Roles in a Playbook

```yaml
# playbooks/site.yml
---
- name: Apply common configuration to all nodes
  hosts: all_lab_nodes
  become: true
  roles:
    - common

- name: Apply hardening to all nodes
  hosts: all_lab_nodes
  become: true
  roles:
    - hardening

- name: Configure managed nodes for Ansible practice
  hosts: managed_nodes
  become: true
  roles:
    - common
    - role: monitoring
      vars:
        monitoring_interval: 60
```

***

## 10. Hardening Playbooks

These playbooks automate security hardening across your lab nodes. They implement CIS benchmark controls adapted for lab use.

### Master Hardening Playbook

```yaml
# playbooks/hardening.yml
---
- name: Linux Security Hardening
  hosts: all_lab_nodes
  become: true

  vars:
    ssh_port: 22
    ssh_permit_root_login: "no"
    ssh_password_auth: "no"
    ssh_max_auth_tries: 3
    ssh_allowed_users:
      - vagrant

    sysctl_hardening:
      # Network hardening
      net.ipv4.ip_forward: 0
      net.ipv4.conf.all.send_redirects: 0
      net.ipv4.conf.default.send_redirects: 0
      net.ipv4.conf.all.accept_redirects: 0
      net.ipv4.conf.default.accept_redirects: 0
      net.ipv4.conf.all.accept_source_route: 0
      net.ipv4.conf.all.log_martians: 1
      net.ipv4.tcp_syncookies: 1
      net.ipv6.conf.all.accept_redirects: 0

      # Kernel hardening
      kernel.randomize_va_space: 2
      kernel.dmesg_restrict: 1
      kernel.kptr_restrict: 2
      fs.protected_hardlinks: 1
      fs.protected_symlinks: 1

  handlers:
    - name: Restart sshd
      ansible.builtin.service:
        name: "{{ 'ssh' if ansible_os_family == 'Debian' else 'sshd' }}"
        state: restarted

    - name: Apply sysctl settings
      ansible.builtin.command: sysctl --system

  tasks:
    # ---- SSH Hardening ---- #
    - name: Ensure SSH is installed
      ansible.builtin.package:
        name: openssh-server
        state: present

    - name: Deploy hardened sshd_config
      ansible.builtin.template:
        src: templates/sshd_config.j2
        dest: /etc/ssh/sshd_config
        owner: root
        group: root
        mode: '0600'
        validate: /usr/sbin/sshd -t -f %s
      notify: Restart sshd

    # ---- Kernel / sysctl Hardening ----
    - name: Apply sysctl hardening parameters
      ansible.posix.sysctl:
        name: "{{ item.key }}"
        value: "{{ item.value }}"
        sysctl_set: true
        state: present
        reload: true
      loop: "{{ sysctl_hardening | dict2items }}"
      notify: Apply sysctl settings

    # ---- Package Hygiene ----
    - name: Remove unnecessary packages (Debian)
      ansible.builtin.apt:
        name:
          - telnet
          - rsh-client
          - rsh-redone-client
          - nis
          - talk
          - inetutils-telnetd
        state: absent
        purge: true
      when: ansible_os_family == "Debian"
      ignore_errors: true

    - name: Remove unnecessary packages (RedHat)
      ansible.builtin.dnf:
        name:
          - telnet
          - rsh
          - ypbind
          - talk
        state: absent
      when: ansible_os_family == "RedHat"
      ignore_errors: true

    # ---- Firewall ----
    - name: Install and enable UFW (Debian)
      block:
        - ansible.builtin.apt:
            name: ufw
            state: present
        - community.general.ufw:
            state: enabled
            policy: deny
        - community.general.ufw:
            rule: allow
            port: "{{ ssh_port }}"
            proto: tcp
      when: ansible_os_family == "Debian"

    - name: Enable and configure firewalld (RedHat)
      block:
        - ansible.builtin.service:
            name: firewalld
            state: started
            enabled: true
        - ansible.posix.firewalld:
            service: ssh
            permanent: true
            state: enabled
        - ansible.posix.firewalld:
            service: telnet
            permanent: true
            state: disabled
      when: ansible_os_family == "RedHat"

    # ---- User and Password Policy ----
    - name: Set password expiry policy (Debian)
      ansible.builtin.lineinfile:
        path: /etc/login.defs
        regexp: "^{{ item.key }}"
        line: "{{ item.key }}\t{{ item.value }}"
      loop:
        - { key: PASS_MAX_DAYS, value: "90" }
        - { key: PASS_MIN_DAYS, value: "1" }
        - { key: PASS_WARN_AGE, value: "7" }

    - name: Ensure sudo group exists and vagrant is in it
      ansible.builtin.user:
        name: vagrant
        groups: sudo
        append: true
      when: ansible_os_family == "Debian"

    # ---- File Permissions ----
    - name: Set correct permissions on sensitive files
      ansible.builtin.file:
        path: "{{ item.path }}"
        mode: "{{ item.mode }}"
        owner: root
        group: root
      loop:
        - { path: /etc/passwd, mode: '0644' }
        - { path: /etc/shadow, mode: '0640' }
        - { path: /etc/group, mode: '0644' }
        - { path: /etc/gshadow, mode: '0640' }
        - { path: /etc/ssh/sshd_config, mode: '0600' }

    # ---- Audit Logging ----
    - name: Install auditd
      ansible.builtin.package:
        name: "{{ 'auditd' if ansible_os_family == 'Debian' else 'audit' }}"
        state: present

    - name: Enable and start auditd
      ansible.builtin.service:
        name: auditd
        state: started
        enabled: true

    - name: Add audit rules for sensitive files
      ansible.builtin.blockinfile:
        path: /etc/audit/rules.d/hardening.rules
        create: true
        block: |
          -w /etc/passwd -p wa -k passwd_changes
          -w /etc/shadow -p wa -k shadow_changes
          -w /etc/sudoers -p wa -k sudoers_changes
          -w /var/log/auth.log -p wa -k auth_log
          -a always,exit -F arch=b64 -S execve -k exec_commands

    # ---- MOTD ----
    - name: Deploy MOTD
      ansible.builtin.template:
        src: templates/motd.j2
        dest: /etc/motd
        mode: '0644'
```

### Running the Hardening Playbook

```bash
# Dry run first
ansible-playbook playbooks/hardening.yml --check --diff

# Run against all lab nodes
ansible-playbook playbooks/hardening.yml

# Run only against Ubuntu nodes
ansible-playbook playbooks/hardening.yml --limit ubuntu_nodes

# Run only SSH hardening tasks
ansible-playbook playbooks/hardening.yml --tags "ssh"

# Verify hardening was applied
ansible all -m command -a "sshd -T | grep -E 'permitroot|passwordauth|maxauthtries'"
```

### Package Audit Playbook

```yaml
# playbooks/audit-packages.yml
---
- name: Audit installed packages across all nodes
  hosts: all_lab_nodes
  become: true

  tasks:
    - name: List all installed packages (Debian)
      ansible.builtin.command: dpkg-query -W -f='${Package} ${Version}\n'
      register: packages_debian
      when: ansible_os_family == "Debian"
      changed_when: false

    - name: List all installed packages (RedHat)
      ansible.builtin.command: rpm -qa --qf '%{NAME} %{VERSION}\n'
      register: packages_redhat
      when: ansible_os_family == "RedHat"
      changed_when: false

    - name: Save package list to file
      ansible.builtin.copy:
        content: "{{ packages_debian.stdout | default(packages_redhat.stdout) }}"
        dest: "/tmp/packages_{{ inventory_hostname }}.txt"
      delegate_to: localhost
```

***

## 11. Vault — Encrypting Secrets

Never store passwords or API keys in plaintext in playbooks or variable files.

```bash
# Create an encrypted vars file
ansible-vault create vars/secrets.yml

# Edit an encrypted file
ansible-vault edit vars/secrets.yml

# Encrypt an existing file
ansible-vault encrypt vars/existing.yml

# Decrypt a file
ansible-vault decrypt vars/existing.yml

# View without decrypting in place
ansible-vault view vars/secrets.yml

# Encrypt a single string value
ansible-vault encrypt_string 'MySecretPassword' --name 'db_password'
```

### Vault-Encrypted Variables File

```yaml
# vars/secrets.yml (encrypted at rest)
db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  3361323534306239623132383...

admin_token: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  6634336432303766663166363...
```

### Using Vault in Playbooks

```bash
# Run with vault password prompt
ansible-playbook playbooks/hardening.yml --ask-vault-pass

# Run with vault password from file
echo "myvaultpassword" > ~/.vault_pass
chmod 600 ~/.vault_pass
ansible-playbook playbooks/hardening.yml --vault-password-file ~/.vault_pass

# Add to ansible.cfg to use automatically
# vault_password_file = ~/.vault_pass
```

***

## 12. Ansible Galaxy

Galaxy hosts community roles and collections.

```bash
# Install a role from Galaxy
ansible-galaxy role install geerlingguy.security
ansible-galaxy role install dev-sec.os-hardening

# Install a collection
ansible-galaxy collection install community.general
ansible-galaxy collection install ansible.posix
ansible-galaxy collection install community.crypto

# Create a requirements file
cat > requirements.yml << 'EOF'
roles:
  - name: dev-sec.os-hardening
  - name: geerlingguy.security

collections:
  - name: community.general
  - name: ansible.posix
  - name: community.crypto
EOF
```

```bash
# Install from requirements
ansible-galaxy install -r requirements.yml
```

***

## 13. Testing with Molecule

Molecule lets you test roles in disposable environments before applying them to the lab.

```bash
# Initialize a new scenario
molecule init scenario -r hardening -d docker

# Run the full test suite
molecule test

# Converge without verification
molecule converge

# Run verification only
molecule verify
```

A common workflow is to run `molecule test` locally, then apply the role to the lab only after the tests pass.

***

## 14. Troubleshooting

### SSH Connectivity Fails

- Check that the target host is up and reachable.
- Verify the inventory uses the correct `ansible_host` value.
- Confirm the SSH key is present on the managed node.

### Playbook Fails on a Package Task

- Confirm the node uses the expected package manager.
- Make sure the relevant collection is installed.
- Run with `--check --diff` first to narrow down the failing task.

### Sysctl Changes Do Not Persist

- Confirm `ansible.posix` is installed.
- Check whether another service rewrites `/etc/sysctl.d`.
- Re-run the playbook and verify the handler executed.

### Vault Prompts Unexpectedly

- Confirm the vault password file path in `ansible.cfg`.
- Make sure the file is readable only by the control user.
- Use `ansible-vault view` to verify the encrypted variables file is valid.

***

## Notes

This guide assumes the control node is `devops-1` and the managed nodes are reachable over the `192.168.121.0/24` network. If you add more nodes later, extend the inventory groups and keep the naming convention consistent.
