# shellcheck shell=bash
echo "nameserver @@DC_IP@@" > /etc/resolv.conf
echo "search @@DOMAIN_NAME@@" >> /etc/resolv.conf
