# shellcheck shell=bash
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
hostnamectl set-hostname kali.lab.local
apt-get update -y
apt-get install -y \
  -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  python3-pip python3-venv bloodhound neo4j
pip3 install --break-system-packages \
  certipy-ad coercer krbrelay targeted-kerberoast ldapdomaindump pywerview bloodhound \
  awscli localstack boto3 awscliv2 \
  impacket evil-winrm bloodyAD Certipy krbrelayx \
  pacu cloudsplaining iam-explorer \
  garak promptfoo langchain langchain-community
echo "Kali ready with modern AD, cloud & LLM tools"
