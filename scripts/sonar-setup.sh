#!/usr/bin/env bash
# Idempotent SonarQube day-0 setup: admin password, Jenkins token -> SSM, webhook -> Jenkins.
# fast-track kit: waits for the StatefulSet with a timeout, re-opens the port-forward inside the loop,
# and never fails the whole bootstrap (it warns instead) - the shop must come up even if Sonar does not.
set -uo pipefail
NS=sonarqube; SVC=sonarqube-sonarqube; S=http://localhost:19000
warn() { echo "WARN sonar-setup: $*"; exit 0; }
echo "waiting for sts/$SVC (up to 15 min)..."
for i in $(seq 1 90); do kubectl -n "$NS" get sts "$SVC" >/dev/null 2>&1 && break; sleep 10; done
kubectl -n "$NS" rollout status "sts/$SVC" --timeout=15m || warn "SonarQube not ready - run this script again later"
NEWPW=$(aws ssm get-parameter --name /roboshop/ci/sonar-admin-password --with-decryption --query Parameter.Value --output text) \
  || warn "missing SSM /roboshop/ci/sonar-admin-password (run scripts/ft-seed-ssm.sh on the laptop)"
PF=""; trap '[ -n "$PF" ] && kill $PF 2>/dev/null' EXIT
up=no
for i in $(seq 1 30); do
  if [ -z "$PF" ] || ! kill -0 "$PF" 2>/dev/null; then
    kubectl -n "$NS" port-forward "svc/$SVC" 19000:9000 >/dev/null 2>&1 & PF=$!; sleep 3
  fi
  curl -sf "$S/api/system/status" | grep -q '"UP"' && { up=yes; break; }
  echo "waiting for sonarqube API ($i/30)..."; sleep 10
done
[ "$up" = yes ] || warn "SonarQube API not UP after 5 min"
# 1. change default password (fails harmlessly if already changed)
curl -sf -u admin:admin -X POST "$S/api/users/change_password" -d "login=admin&previousPassword=admin&password=$NEWPW" >/dev/null && echo "admin password set" || true
A="admin:$NEWPW"
# 2. fresh token for Jenkins (revoke the old one with the same name first)
curl -s -u "$A" -X POST "$S/api/user_tokens/revoke" -d "name=jenkins" >/dev/null || true
TOKEN=$(curl -sf -u "$A" -X POST "$S/api/user_tokens/generate" -d "name=jenkins" | jq -r .token)
[ -n "$TOKEN" ] && [ "$TOKEN" != null ] || warn "could not create a token (wrong admin password in SSM?)"
aws ssm put-parameter --name /roboshop/ci/sonar-token --type SecureString --overwrite --value "$TOKEN" >/dev/null \
  && echo "token stored in SSM /roboshop/ci/sonar-token" || warn "PutParameter denied - apply 10-foundation (WriteSonarToken statement)"
# 3. webhook so waitForQualityGate gets the result
curl -sf -u "$A" -X POST "$S/api/webhooks/create" \
  -d "name=jenkins&url=http://jenkins.jenkins.svc.cluster.local:8080/sonarqube-webhook/" >/dev/null && echo "webhook created" || echo "webhook exists"
kubectl -n jenkins annotate externalsecret jenkins-credentials force-sync="$(date +%s)" --overwrite >/dev/null 2>&1 || true
