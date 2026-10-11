#!/usr/bin/env bash
# Legacy RoboShop, step 2: Node.js services (catalogue, user, cart) under systemd as user roboshop.
set -euo pipefail
APP=~/work/roboshop-app
NODE_STREAM="${NODE_STREAM:-20}"

sudo dnf module reset -y -q nodejs
sudo dnf module enable -y -q "nodejs:${NODE_STREAM}"
sudo dnf install -y -q nodejs
id roboshop >/dev/null 2>&1 || sudo useradd --system --home-dir /opt/roboshop --create-home --shell /sbin/nologin roboshop

declare -A PORT=( [catalogue]=8081 [user]=8082 [cart]=8083 )
declare -A ENVS=(
  [catalogue]="MONGO_URL=mongodb://127.0.0.1:27017/catalogue"
  [user]="MONGO_URL=mongodb://127.0.0.1:27017/users REDIS_HOST=127.0.0.1"
  [cart]="REDIS_HOST=127.0.0.1 CATALOGUE_HOST=127.0.0.1 CATALOGUE_PORT=8081"
)
for s in catalogue user cart; do
  sudo mkdir -p /opt/roboshop/$s
  sudo cp "$APP/$s/package.json" "$APP/$s/server.js" /opt/roboshop/$s/
  sudo chown -R roboshop:roboshop /opt/roboshop/$s
  sudo -u roboshop -H bash -c "cd /opt/roboshop/$s && npm install --omit=dev --no-audit --no-fund --loglevel=error"
  UP=$(echo "$s" | tr a-z A-Z)
  {
    echo "[Unit]"; echo "Description=RoboShop $s (Node.js)"
    echo "After=network-online.target docker.service"; echo "Wants=network-online.target"
    echo; echo "[Service]"; echo "User=roboshop"; echo "Group=roboshop"
    echo "WorkingDirectory=/opt/roboshop/$s"
    echo "Environment=${UP}_SERVER_PORT=${PORT[$s]}"
    for e in ${ENVS[$s]}; do echo "Environment=$e"; done
    echo "ExecStart=/usr/bin/node server.js"; echo "Restart=on-failure"; echo "RestartSec=5"
    echo; echo "[Install]"; echo "WantedBy=multi-user.target"
  } | sudo tee /etc/systemd/system/roboshop-$s.service >/dev/null
done
sudo systemctl daemon-reload
sudo systemctl enable --now roboshop-catalogue roboshop-user roboshop-cart
sudo systemctl restart roboshop-catalogue roboshop-user roboshop-cart
echo "node services up"
