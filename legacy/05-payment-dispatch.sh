#!/usr/bin/env bash
# Legacy RoboShop, step 5: Python payment (venv + uWSGI) and Go dispatch.
set -euo pipefail
APP=~/work/roboshop-app; F=~/work/roboshop-infra/legacy/files
sudo dnf install -y -q python3 python3-devel gcc golang
# payment
sudo mkdir -p /opt/roboshop/payment
sudo cp "$APP"/payment/*.py "$F/payment.ini" "$F/payment-requirements.lock.txt" /opt/roboshop/payment/
sudo chown -R roboshop:roboshop /opt/roboshop/payment
sudo -u roboshop -H bash -c 'cd /opt/roboshop/payment && [ -d venv ] || python3 -m venv venv; venv/bin/pip install -q -r payment-requirements.lock.txt'
# dispatch
rm -rf ~/build/dispatch && mkdir -p ~/build/dispatch
cp "$APP/dispatch/main.go" "$F/go.mod" "$F/go.sum" ~/build/dispatch/
( cd ~/build/dispatch && CGO_ENABLED=0 go build -o dispatch . )
sudo install -o roboshop -g roboshop -m 0755 -D ~/build/dispatch/dispatch /opt/roboshop/dispatch/dispatch
# units
sudo cp "$F/roboshop-payment.service" "$F/roboshop-dispatch.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now roboshop-payment roboshop-dispatch
sudo systemctl restart roboshop-payment roboshop-dispatch
echo "payment + dispatch up"
