#!/usr/bin/env bash
# Legacy RoboShop, step 3: nginx on :80 serving static web + /api reverse proxy.
set -euo pipefail
INFRA=~/work/roboshop-infra
sudo dnf install -y -q nginx
sudo mkdir -p /opt/roboshop/web
sudo cp -r ~/work/roboshop-app/web/static/. /opt/roboshop/web/
sudo cp /opt/roboshop/web/empty.html /opt/roboshop/web/eum.html
sudo chmod -R a+rX /opt/roboshop/web
sudo cp "$INFRA/legacy/files/nginx.conf"    /etc/nginx/nginx.conf
sudo cp "$INFRA/legacy/files/roboshop.conf" /etc/nginx/conf.d/roboshop.conf
if [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
  sudo setsebool -P httpd_can_network_connect 1
  sudo semanage fcontext -a -t httpd_sys_content_t "/opt/roboshop/web(/.*)?" 2>/dev/null || true
  sudo restorecon -R /opt/roboshop/web
fi
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
echo "web up on :80"
