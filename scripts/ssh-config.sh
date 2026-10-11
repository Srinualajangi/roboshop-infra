#!/usr/bin/env bash
# roboshop-infra/scripts/ssh-config.sh  - (re)writes the "roboshop-lab" block in ~/.ssh/config
# SSH runs *inside* an SSM session, so no port is open. The instance ID changes daily, so we rewrite it.
set -euo pipefail
IID=$(terraform -chdir=terraform/20-workstation output -raw instance_id)
CFG="${1:-$HOME/.ssh/config}"
mkdir -p "$(dirname "$CFG")" && touch "$CFG"
sed -i '/# >>> roboshop-lab >>>/,/# <<< roboshop-lab <<</d' "$CFG"     # macOS: sed -i ''
cat >> "$CFG" <<EOF
# >>> roboshop-lab >>>  (managed by roboshop-infra/scripts/ssh-config.sh - do not edit)
Host roboshop-lab
  HostName $IID
  User ec2-user
  IdentityFile ~/.ssh/roboshop_lab
  ForwardAgent yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
  ServerAliveInterval 30
  ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region us-east-1 --profile ${AWS_PROFILE:-roboshop}"
# <<< roboshop-lab <<<
EOF
echo "ssh roboshop-lab  ->  $IID"
