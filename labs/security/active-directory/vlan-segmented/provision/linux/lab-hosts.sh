# shellcheck shell=bash
      sed -i '/172\.28\./d' /etc/hosts
      cat <<EOF >> /etc/hosts
# --- Lab VMs (VLAN IP scheme) ---
172.28.99.10  kali.lab.local        kali
172.28.10.21  dc01.lab.local        dc01
172.28.10.23  db01.lab.local        db01
172.28.10.25  ca01-esc.lab.local    ca01-esc
172.28.20.30  win10.lab.local       win10
172.28.30.60  llm01.lab.local       llm01
172.28.30.72  linux01.lab.local     linux01
172.28.30.73  print01.lab.local     print01
172.28.30.80  cloud-pentest.lab.local cloud-pentest
172.28.40.12  metasploitable2.lab.local metasploitable2
172.28.40.15  juice-shop.lab.local  juice-shop
EOF
