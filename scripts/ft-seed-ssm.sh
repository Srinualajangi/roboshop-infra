#!/usr/bin/env bash
# fast-track kit: create EVERY SSM parameter the end state reads, in one go. Run on the LAPTOP (the workstation
# role can only read /roboshop/*). Idempotent: existing parameters are never overwritten (use --rotate to force).
# Names are the ones the files actually use (the Reference page table in the guide is out of date).
#   usage: scripts/ft-seed-ssm.sh            create what is missing
#          scripts/ft-seed-ssm.sh --list     show names + last-modified (never the values)
#          scripts/ft-seed-ssm.sh --rotate   regenerate every random value (restart the apps afterwards)
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-roboshop} AWS_REGION=${AWS_REGION:-us-east-1}
MODE=${1:-create}
rnd() { openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c "${1:-20}"; }

put() {   # put <name> <value> <description>
  local name=$1 value=$2 desc=$3 exists=no
  aws ssm get-parameter --name "$name" >/dev/null 2>&1 && exists=yes
  if [ "$exists" = yes ] && [ "$MODE" != --rotate ]; then printf '  = %-45s (exists, kept)\n' "$name"; return; fi
  aws ssm put-parameter --name "$name" --type SecureString --value "$value" --description "$desc" \
    $( [ "$exists" = yes ] && echo --overwrite ) >/dev/null
  printf '  + %-45s %s\n' "$name" "$( [ "$exists" = yes ] && echo rotated || echo created)"
}

if [ "$MODE" = --list ]; then
  aws ssm get-parameters-by-path --path /roboshop --recursive \
    --query 'Parameters[].[Name,Type,LastModifiedDate]' --output table
  exit 0
fi

echo "core (needed by every boot)"
for env in dev qa prod; do
  put "/roboshop/$env/mysql-root-password" "$(rnd 20)" "RoboShop $env MySQL root (Day 42/54)"
  put "/roboshop/$env/rabbitmq/username"   "roboshop"   "RoboShop $env RabbitMQ user (Day 54)"
  put "/roboshop/$env/rabbitmq/password"   "$(rnd 20)" "RoboShop $env RabbitMQ password (Day 54)"
done

echo "obs profile"
put /roboshop/monitoring/grafana-admin "$(rnd 20)" "Grafana admin password (Day 75)"

echo "ci profile"
put /roboshop/ci/jenkins-admin              "$(rnd 20)" "Jenkins admin password (Day 69)"
put /roboshop/ci/sonar-db-password          "$(rnd 32)" "SonarQube PostgreSQL (Day 71)"
put /roboshop/ci/sonar-monitoring-passcode  "$(rnd 32)" "SonarQube monitoring passcode (Day 71)"
put /roboshop/ci/sonar-admin-password       "$(rnd 20)" "SonarQube admin password (Day 71)"
# Rewritten at every boot by scripts/sonar-setup.sh; a placeholder lets Jenkins start before Sonar is ready.
[ "$MODE" = --rotate ] || put /roboshop/ci/sonar-token "placeholder-until-sonar-setup" "SonarQube token for Jenkins (Day 71)"
# A GitHub fine-grained PAT (Contents + Pull requests R/W on roboshop-gitops only). Placeholder until you create it.
if ! aws ssm get-parameter --name /roboshop/ci/gitops-token >/dev/null 2>&1; then
  put /roboshop/ci/gitops-token "placeholder-create-a-PAT" "GitHub PAT for roboshop-gitops (Day 73)"
  echo "    -> replace later:  read -rs -p 'GitOps PAT: ' T && aws ssm put-parameter --name /roboshop/ci/gitops-token --type SecureString --overwrite --value \"\$T\" && unset T"
fi

echo
echo "Optional, only for the Day 81 Slack drill:"
echo "  aws ssm put-parameter --name /roboshop/monitoring/slack-webhook --type SecureString --value 'https://hooks.slack.com/services/...'"
echo "Done. List them (names only):  scripts/ft-seed-ssm.sh --list"
