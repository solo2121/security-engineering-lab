# shellcheck shell=sh
            sleep 60
            /usr/local/sbin/configctl interface reconfigure
            /usr/local/sbin/configctl dhcpd restart
            /usr/local/sbin/configctl filter reload
            touch /root/opnsense-configured
            echo "OPNSENSE CONFIGURED SUCCESSFULLY"
