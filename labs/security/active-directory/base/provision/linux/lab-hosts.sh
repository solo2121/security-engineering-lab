# shellcheck shell=bash
      # Remove old lab entries and add fresh ones
      sed -i '/172\.28\.128/d' /etc/hosts
      cat <<EOF >> /etc/hosts
@@KALI_IP@@ kali.lab.local kali
@@DC01_IP@@ dc01.lab.local dc01
@@DB01_IP@@ db01.lab.local db01
@@WIN10_IP@@ win10.lab.local win10
@@LLM01_IP@@ llm01.lab.local llm01
@@LINUX01_IP@@ linux01.lab.local linux01
@@PRINT01_IP@@ print01.lab.local print01
@@METASPLOITABLE2_IP@@ metasploitable2.lab.local metasploitable2
@@JUICE_SHOP_IP@@ juice-shop.lab.local juice-shop
@@CLOUD_PENTEST_IP@@ cloud-pentest.lab.local cloud-pentest
@@CA01_ESC_IP@@ ca01-esc.lab.local ca01-esc
EOF
