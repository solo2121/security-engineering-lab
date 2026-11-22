# shellcheck shell=bash
echo "Configuring Kali VM"
mkdir -p /var/log/lab

hostnamectl set-hostname kali.lab.local

apt-get update -y
apt-get install -y python3-pip python3-venv bloodhound neo4j
pip3 install --break-system-packages certipy-ad coercer krbrelay targeted-kerberoast ldapdomaindump pywerview bloodhound
pip3 install --break-system-packages awscli localstack boto3 awscliv2
pip3 install --break-system-packages pypykatz pywhisker msldap dnspython

echo "Kali ready with modern AD, cloud & LLM tools" | tee -a /var/log/lab/kali-setup.log
