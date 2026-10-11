#!/usr/bin/env bash
# Legacy RoboShop, step 4: Java shipping service (Maven build -> fat jar -> systemd).
set -euo pipefail
sudo dnf install -y -q java-17-openjdk-devel maven
rm -rf ~/build/shipping && mkdir -p ~/build && cp -r ~/work/roboshop-app/shipping ~/build/
( cd ~/build/shipping && mvn -q -DskipTests package )
sudo mkdir -p /opt/roboshop/shipping
sudo cp ~/build/shipping/target/shipping-1.0.jar /opt/roboshop/shipping/shipping.jar
sudo chown -R roboshop:roboshop /opt/roboshop/shipping
sudo cp ~/work/roboshop-infra/legacy/files/roboshop-shipping.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now roboshop-shipping
sudo systemctl restart roboshop-shipping
echo -n "waiting for shipping"; until curl -sf localhost:8084/health >/dev/null; do echo -n .; sleep 3; done; echo " up"
