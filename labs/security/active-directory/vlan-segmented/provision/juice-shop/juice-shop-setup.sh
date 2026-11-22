# shellcheck shell=bash
echo "Configuring Juice Shop"
mkdir -p /var/log/lab
apt-get update
apt-get install -y docker.io
systemctl start docker
systemctl enable docker
docker pull bkimminich/juice-shop
docker run -d --restart=always --name juice-shop -p 80:3000 bkimminich/juice-shop
echo "Juice Shop running at http://172.28.40.15" | tee -a /var/log/lab/juice-shop-setup.log
