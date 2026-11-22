# shellcheck shell=sh
            echo "================================================================================"
            echo "OPNSENSE INITIAL CONFIGURATION (@@PROVIDER_UPPER@@)"
            echo "================================================================================"

            sleep 60

            @@OPNSENSE_IFACE_COMMENT@@
            cat > /conf/config.xml <<'EOF'
            <?xml version="1.0"?>
            <opnsense>
              <version>24.7</version>
              <system>
                <hostname>opnsense</hostname>
                <domain>lab.local</domain>
                <group>
                  <name>admins</name>
                  <description>System Administrators</description>
                  <scope>system</scope>
                  <gid>1999</gid>
                  <member>0</member>
                  <priv>page-all</priv>
                </group>
                <user>
                  <name>root</name>
                  <descr>System Administrator</descr>
                  <scope>system</scope>
                  <groupname>admins</groupname>
                  <password>$2y$10$nHvwHs9PtSI9QiAujjP8Mu7Bpk.Hl1xOKlYIetxdj5yuIj/J98BXu</password>
                  <uid>0</uid>
                </user>
                <timezone>UTC</timezone>
                <webgui>
                  <protocol>http</protocol>
                  <port>80</port>
                  <disable_redirect>1</disable_redirect>
                </webgui>
                <ssh>
                  <enabled>1</enabled>
                  <port>22</port>
                  <permitrootlogin>1</permitrootlogin>
                  <passwordauth>1</passwordauth>
                </ssh>
              </system>
              <interfaces>
                <wan><if>vtnet1</if><enable>1</enable><ipaddr>192.168.100.2</ipaddr><subnet>24</subnet><gateway>192.168.100.1</gateway><descr>WAN</descr><blockpriv>0</blockpriv><blockbogons>0</blockbogons></wan>
                <lan><if>vtnet2</if><enable>1</enable><ipaddr>172.28.10.1</ipaddr><subnet>24</subnet><descr>Management VLAN</descr><blockpriv>0</blockpriv><blockbogons>0</blockbogons></lan>
                <opt1><if>vtnet3</if><enable>1</enable><ipaddr>172.28.20.1</ipaddr><subnet>24</subnet><descr>Workstations VLAN</descr><blockpriv>0</blockpriv><blockbogons>0</blockbogons></opt1>
                <opt2><if>vtnet4</if><enable>1</enable><ipaddr>172.28.30.1</ipaddr><subnet>24</subnet><descr>Servers VLAN</descr><blockpriv>0</blockpriv><blockbogons>0</blockbogons></opt2>
                <opt3><if>vtnet5</if><enable>1</enable><ipaddr>172.28.40.1</ipaddr><subnet>24</subnet><descr>DMZ VLAN</descr><blockpriv>0</blockpriv><blockbogons>0</blockbogons></opt3>
                <opt4><if>vtnet6</if><enable>1</enable><ipaddr>172.28.99.1</ipaddr><subnet>24</subnet><descr>Attacker VLAN</descr><blockpriv>0</blockpriv><blockbogons>0</blockbogons></opt4>
                <!-- vtnet0 is vagrant-libvirt's implicit management NIC (192.168.121.0/24 by
                     default), attached to every VM automatically in addition to the interfaces
                     declared in the Vagrantfile. It carries no lab traffic and is not part of
                     the WAN/LAN/VLAN topology. Left unassigned here, OPNsense drops it on
                     configctl interface reconfigure, which breaks Vagrant's SSH reconnection
                     after the post-init reboot. Assigning it DHCP (with no gateway entry below,
                     so it cannot become the default route) keeps it reachable for Vagrant only. -->
                <opt5><if>vtnet0</if><enable>1</enable><ipaddr>dhcp</ipaddr><descr>Vagrant Management (do not use for lab traffic)</descr><blockpriv>0</blockpriv><blockbogons>0</blockbogons></opt5>
              </interfaces>
              <gateways>
                <gateway_item><interface>wan</interface><gateway>192.168.100.1</gateway><name>WAN_GW</name><weight>1</weight><ipprotocol>inet</ipprotocol><descr>Default Gateway</descr></gateway_item>
              </gateways>
              <dhcpd>
                <lan><enable>1</enable><range><from>172.28.10.100</from><to>172.28.10.200</to></range><domain>lab.local</domain><dnsserver>172.28.10.21</dnsserver><gateway>172.28.10.1</gateway><subnet>255.255.255.0</subnet><defaultleasetime>86400</defaultleasetime><maxleasetime>172800</maxleasetime></lan>
                <opt1><enable>1</enable><range><from>172.28.20.100</from><to>172.28.20.200</to></range><domain>lab.local</domain><dnsserver>172.28.10.21</dnsserver><gateway>172.28.20.1</gateway><subnet>255.255.255.0</subnet><defaultleasetime>86400</defaultleasetime><maxleasetime>172800</maxleasetime></opt1>
                <opt2><enable>1</enable><range><from>172.28.30.100</from><to>172.28.30.200</to></range><domain>lab.local</domain><dnsserver>172.28.10.21</dnsserver><gateway>172.28.30.1</gateway><subnet>255.255.255.0</subnet><defaultleasetime>86400</defaultleasetime><maxleasetime>172800</maxleasetime></opt2>
                <opt3><enable>1</enable><range><from>172.28.40.100</from><to>172.28.40.200</to></range><domain>lab.local</domain><dnsserver>172.28.10.21</dnsserver><gateway>172.28.40.1</gateway><subnet>255.255.255.0</subnet><defaultleasetime>86400</defaultleasetime><maxleasetime>172800</maxleasetime></opt3>
                <opt4><enable>1</enable><range><from>172.28.99.100</from><to>172.28.99.200</to></range><domain>lab.local</domain><dnsserver>172.28.10.21</dnsserver><gateway>172.28.99.1</gateway><subnet>255.255.255.0</subnet><defaultleasetime>86400</defaultleasetime><maxleasetime>172800</maxleasetime></opt4>
              </dhcpd>
              <filter>
                <rule><type>pass</type><interface>wan</interface><ipprotocol>inet</ipprotocol><protocol>any</protocol><source><network>any</network></source><destination><any></any></destination><descr>Allow all OUT on WAN</descr></rule>
                <rule><type>pass</type><interface>lan</interface><ipprotocol>inet</ipprotocol><protocol>any</protocol><source><network>lan</network></source><destination><any></any></destination><descr>Allow LAN to any</descr></rule>
                <rule><type>pass</type><interface>opt1</interface><ipprotocol>inet</ipprotocol><protocol>any</protocol><source><network>opt1</network></source><destination><any></any></destination><descr>Allow Workstations to any</descr></rule>
                <rule><type>pass</type><interface>opt2</interface><ipprotocol>inet</ipprotocol><protocol>any</protocol><source><network>opt2</network></source><destination><any></any></destination><descr>Allow Servers to any</descr></rule>
                <rule><type>pass</type><interface>opt3</interface><ipprotocol>inet</ipprotocol><protocol>any</protocol><source><network>opt3</network></source><destination><any></any></destination><descr>Allow DMZ to any</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>udp</protocol><source><network>opt4</network></source><destination><address>172.28.10.21</address><port>53</port></destination><descr>Allow DNS to DC01</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>tcp</protocol><source><network>opt4</network></source><destination><address>172.28.10.21</address><port>53</port></destination><descr>Allow DNS to DC01</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>tcp</protocol><source><network>opt4</network></source><destination><address>172.28.10.21</address><port>88</port></destination><descr>Allow Kerberos TCP</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>udp</protocol><source><network>opt4</network></source><destination><address>172.28.10.21</address><port>88</port></destination><descr>Allow Kerberos UDP</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>tcp</protocol><source><network>opt4</network></source><destination><address>172.28.10.21</address><port>135</port></destination><descr>Allow RPC</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>tcp</protocol><source><network>opt4</network></source><destination><address>172.28.10.21</address><port>139</port></destination><descr>Allow NetBIOS</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>tcp</protocol><source><network>opt4</network></source><destination><address>172.28.10.21</address><port>445</port></destination><descr>Allow SMB</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>tcp</protocol><source><network>opt4</network></source><destination><address>172.28.10.21</address><port>389</port></destination><descr>Allow LDAP</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>udp</protocol><source><network>opt4</network></source><destination><address>172.28.10.21</address><port>389</port></destination><descr>Allow LDAP</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>tcp</protocol><source><network>opt4</network></source><destination><address>172.28.10.21</address><port>464</port></destination><descr>Allow Kerberos Password Change</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>tcp</protocol><source><network>opt4</network></source><destination><address>172.28.10.21</address><port>5985</port></destination><descr>Allow WinRM</descr></rule>
                <rule><type>pass</type><interface>opt4</interface><ipprotocol>inet</ipprotocol><protocol>icmp</protocol><source><network>opt4</network></source><destination><any></any></destination><descr>Allow ICMP</descr></rule>
              </filter>
            </opnsense>
EOF

            chown root:wheel /conf/config.xml
            chmod 600 /conf/config.xml

            /usr/local/sbin/configctl interface reconfigure
            /usr/local/sbin/configctl dhcpd restart
            /usr/local/sbin/configctl filter reload
            /usr/local/sbin/configctl webgui restart
            /usr/local/sbin/configctl openssh restart
