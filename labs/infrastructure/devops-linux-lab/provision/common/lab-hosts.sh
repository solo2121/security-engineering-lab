# shellcheck shell=bash
        set -e
        START="# LAB START"
        END="# LAB END"
        sed -i "/$START/,/$END/d" /etc/hosts 2>/dev/null || true
        cat >> /etc/hosts <<EOF
$START
@@HOSTS_ENTRIES@@
$END
EOF
