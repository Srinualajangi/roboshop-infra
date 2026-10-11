#!/usr/bin/env bash
# roboshop-infra/workstation/bootstrap.sh
# Runs as root from user_data on every new workstation. Rebuilds "yesterday" from Git:
# installs the AWS CLI, then runs every step in lab.env as ec2-user, reporting status to SSM.
set -euo pipefail
exec > >(tee -a /var/log/roboshop-bootstrap.log) 2>&1

HERE="$(cd "$(dirname "$0")" && pwd)"          # /opt/roboshop-infra/workstation
INFRA_DIR="$(dirname "$HERE")"
export PATH=/usr/local/bin:$PATH                # the AWS CLI installer links aws here
: "${GH_USER:?GH_USER must be set}" "${INSTANCE_ID:?INSTANCE_ID must be set}"
export AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1
CURRENT=init

ensure_awscli() {
  command -v aws >/dev/null 2>&1 && return 0
  dnf install -y -q unzip
  curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
  unzip -q -o /tmp/awscliv2.zip -d /tmp && /tmp/aws/install --update
}

status() {   # status <state> [detail]  ->  /roboshop/lab/status = <state>-<instance-id>[-detail]
  aws ssm put-parameter --name /roboshop/lab/status --type String --overwrite \
    --value "$1-${INSTANCE_ID}${2:+-$2}" >/dev/null || echo "WARN: could not write status"
}

ensure_awscli
trap 'status failed "$CURRENT"; echo "BOOTSTRAP FAILED in step: $CURRENT"' ERR
status booting
echo "=== bootstrap start $(date -Is) on $INSTANCE_ID ==="

# shellcheck source=/dev/null
source "$HERE/versions.env"
# shellcheck source=/dev/null
source "$HERE/lab.env"
# fast-track kit: "make up-full" (Terraform vars lab_profiles / lab_steps) overrides lab.env for this boot only
LAB_STEPS=${LAB_STEPS_OVERRIDE:-$LAB_STEPS}
LAB_PROFILES=${LAB_PROFILES_OVERRIDE:-${LAB_PROFILES:-}}
echo "steps: $LAB_STEPS | profiles: core ${LAB_PROFILES}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

for step in $LAB_STEPS; do
  CURRENT=$step
  echo "=== step: $step ($(date +%T)) ==="
  sudo -iu ec2-user env GH_USER="$GH_USER" AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID" AWS_REGION="$AWS_REGION" \
    AWS_DEFAULT_REGION="$AWS_REGION" INFRA_DIR="$INFRA_DIR" GIT_NAME="$GIT_NAME" GIT_EMAIL="$GIT_EMAIL" LAB_PROFILES_OVERRIDE="$LAB_PROFILES" \
    bash "$HERE/steps/$step.sh"
done

CURRENT=done
echo "=== bootstrap finished $(date -Is) ==="
cat > /etc/motd <<EOF

  RoboShop lab workstation ($INSTANCE_ID)  -  steps: $LAB_STEPS
  Auto-shutdown is scheduled. Extend from the laptop with: make extend
  Bootstrap log: /var/log/roboshop-bootstrap.log

EOF
status ready
