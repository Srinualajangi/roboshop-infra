#!/usr/bin/env bash
# Step 'legacy' (Phase 2, Day 21): build the legacy RoboShop stack with Ansible.
# Removed from LAB_STEPS on Day 33 when Kubernetes takes over.
set -euo pipefail
cd ~/work/roboshop-infra/ansible
echo "[legacy] installing collections"
ansible-galaxy collection install -r collections/requirements.yml
echo "[legacy] running site.yml"
ANSIBLE_FORCE_COLOR=0 ansible-playbook site.yml
echo "[legacy] health check"
~/work/roboshop-infra/scripts/healthcheck.sh -q
