# shellcheck shell=bash
set -euo pipefail
mkdir -p /home/vagrant/.ssh
chmod 700 /home/vagrant/.ssh

for i in $(seq 1 30); do
  if [ -f /vagrant/ansible_key.pub ]; then
    grep -qF "$(cat /vagrant/ansible_key.pub)" /home/vagrant/.ssh/authorized_keys 2>/dev/null ||               cat /vagrant/ansible_key.pub >> /home/vagrant/.ssh/authorized_keys
    chmod 600 /home/vagrant/.ssh/authorized_keys
    echo "SSH key configured for $(hostname)"
    break
  fi
  echo " Waiting for ansible_key.pub... ($i/30)"; sleep 2
done

if [ ! -f /vagrant/ansible_key.pub ]; then
  echo "WARNING: ansible_key.pub was not found after 60 seconds, so Ansible cannot log in to $(hostname) yet."
  echo "Start devops-1 first (it creates the key), then run: vagrant rsync $(hostname) && vagrant provision $(hostname)"
fi
