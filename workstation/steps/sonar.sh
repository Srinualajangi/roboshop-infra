#!/usr/bin/env bash
# Day 71: SonarQube is rebuilt daily, so re-create the admin password + CI token at boot (runs after root-app).
set -euo pipefail
bash ~/work/roboshop-infra/scripts/sonar-setup.sh
