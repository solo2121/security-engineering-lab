# shellcheck shell=bash
      useradd -m bob_developer || true
      echo "bob_developer:Develop123!" | chpasswd
      usermod -aG sudo bob_developer

      # Secure SSH config while maintaining lab accessibility
      sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
      sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

      # Add vulnerable user for testing
      useradd -m weakuser || true
      echo "weakuser:password" | chpasswd

      # Add some vulnerable cron jobs
      echo "*/5 * * * * root echo 'DB_PASSWORD=DbPass123!' >> /var/log/db.log" >> /etc/crontab

      # Setup vulnerable web config
      mkdir -p /var/www/html
      echo "<?php echo 'DB_PASS=' . getenv('DB_PASS'); ?>" > /var/www/html/config.php

      # Install vulnerable polkit version (CVE-2021-3560)
      echo "=== Installing vulnerable polkit version (CVE-2021-3560) ==="
      apt-get update
      apt-get install -y policykit-1
      cat > /etc/polkit-1/localauthority/50-local.d/vulnerable.pkla << 'EOF'
[Vulnerable Policy]
Identity=unix-user:*
Action=*
ResultActive=yes
ResultInactive=yes
ResultAny=yes
EOF
      systemctl restart polkit || true

      systemctl restart sshd
      echo "Linux01 configured with Polkit vulnerability"
