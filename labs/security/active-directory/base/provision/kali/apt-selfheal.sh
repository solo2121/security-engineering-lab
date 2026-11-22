# shellcheck shell=bash
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
dpkg --configure -a || true
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --fix-broken install || true
echo "[kali-apt-selfheal] dpkg/apt state checked and repaired if needed"
