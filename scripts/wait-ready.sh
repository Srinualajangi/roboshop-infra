#!/usr/bin/env bash
# roboshop-infra/scripts/wait-ready.sh  - polls the status the workstation writes to SSM
set -euo pipefail
IID=$(terraform -chdir=terraform/20-workstation output -raw instance_id)
echo "Waiting for $IID to finish bootstrapping (Ctrl-C is safe; re-run 'make wait')"
WAIT_MIN=${WAIT_MIN:-30}                       # fast-track kit: make up-full waits 45
for i in $(seq 1 $(( WAIT_MIN * 3 ))); do
  v=$(aws ssm get-parameter --name /roboshop/lab/status --query Parameter.Value --output text 2>/dev/null || echo none)
  case "$v" in
    "ready-$IID")    echo; echo "✅ ready after ~$((i * 20))s   ->  ssh roboshop-lab   |   make tunnel"; exit 0 ;;
    "failed-$IID"*)  echo; echo "❌ $v"; echo "Debug: make connect, then: sudo tail -80 /var/log/roboshop-bootstrap.log"; exit 1 ;;
  esac
  printf '.'; sleep 20
done
echo; echo "Timed out after $WAIT_MIN min. make connect and read /var/log/roboshop-bootstrap.log"; exit 1
