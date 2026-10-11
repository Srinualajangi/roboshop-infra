#!/usr/bin/env bash
# fast-track kit: 30-second "will make up work?" check, on the LAPTOP, before you spend money on a boot.
# Checks tools, SSO login, the persistent layers, IAM, ECR images, SSM parameters, placeholders and that the
# workstation can actually clone your repos from GitHub (public + pushed). Read-only; costs ~nothing.
set -uo pipefail
cd "$(dirname "$0")/.."
GITOPS=${GITOPS:-../roboshop-gitops}; APP=${APP:-../roboshop-app}
export AWS_PROFILE=${AWS_PROFILE:-roboshop} AWS_REGION=${AWS_REGION:-us-east-1}
P=0; F=0; W=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; P=$((P+1)); }
bad()  { printf '  \033[31m✘\033[0m %s\n      -> %s\n' "$1" "$2"; F=$((F+1)); }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; W=$((W+1)); }

echo "== laptop tools"
for t in aws session-manager-plugin terraform make git jq curl ssh; do
  command -v $t >/dev/null && ok "$t" || bad "$t missing" "01-golden-setup.md step A3"; done
for t in helm yq; do command -v $t >/dev/null && ok "$t (needed by ft-pin-versions.sh)" || warn "$t missing (only needed to pin versions / EKS)"; done
tfv=$(terraform version -json 2>/dev/null | jq -r .terraform_version 2>/dev/null || echo 0)
[ "$(printf '%s\n1.10.0\n' "$tfv" | sort -V | head -1)" = 1.10.0 ] && ok "terraform $tfv (>= 1.10 for S3 native locking)" || bad "terraform $tfv < 1.10" "upgrade terraform"
[ -f ~/.ssh/roboshop_lab.pub ] && ok "~/.ssh/roboshop_lab.pub" || bad "no ~/.ssh/roboshop_lab key" "ssh-keygen -t ed25519 -f ~/.ssh/roboshop_lab -C roboshop-lab"

echo "== AWS"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  && ok "SSO session valid (account $ACCOUNT, profile $AWS_PROFILE)" \
  || { bad "not logged in" "aws sso login --profile $AWS_PROFILE"; echo "stop: fix login first"; exit 1; }
aws s3api head-bucket --bucket "roboshop-tfstate-$ACCOUNT" 2>/dev/null && ok "state bucket roboshop-tfstate-$ACCOUNT (00-bootstrap)" \
  || bad "no state bucket" "01-golden-setup.md step C1 (00-bootstrap)"
aws iam get-instance-profile --instance-profile-name roboshop-workstation >/dev/null 2>&1 && ok "instance profile roboshop-workstation (10-foundation)" \
  || bad "no workstation instance profile" "make apply LAYER=10-foundation"
pol=$(aws iam get-role-policy --role-name roboshop-workstation --policy-name roboshop-workstation --query PolicyDocument --output json 2>/dev/null)
echo "$pol" | grep -q WriteSonarToken && echo "$pol" | grep -q VeleroBucket && ok "workstation role has the kit's IAM statements" \
  || warn "workstation role lacks WriteSonarToken/VeleroBucket (only needed for ci profile / velero) -> make apply LAYER=10-foundation"
n=$(aws ecr describe-repositories --query 'length(repositories[?starts_with(repositoryName,`roboshop/`)])' --output text 2>/dev/null || echo 0)
[ "$n" -ge 10 ] && ok "ECR repos roboshop/* ($n)" || bad "only $n ECR repos" "make apply LAYER=10-foundation"
missing=""
for e in dev qa prod; do for p in mysql-root-password rabbitmq/username rabbitmq/password; do
  aws ssm get-parameter --name "/roboshop/$e/$p" >/dev/null 2>&1 || missing="$missing /roboshop/$e/$p"; done; done
[ -z "$missing" ] && ok "core SSM parameters (9)" || bad "missing SSM:$missing" "scripts/ft-seed-ssm.sh"
spot=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-34B43A08 --query Quota.Value --output text 2>/dev/null || echo "?")
case "$spot" in ?|None) warn "could not read the Spot vCPU quota";; *) [ "${spot%.*}" -ge 8 ] && ok "Spot vCPU quota $spot" || bad "Spot vCPU quota $spot (< 8)" "Service Quotas -> EC2 -> 'All Standard Spot Instance Requests' -> request 16";; esac

echo "== repos and placeholders"
for f in workstation/versions.env; do
  grep -nE '^[A-Z_]+=[^#]*(PIN_ME|<|[0-9][xXz]|[.v][xX]\.)' "$f" >/dev/null && bad "$f still has placeholders" "scripts/ft-pin-versions.sh" || ok "$f pinned"; done
if [ -d "$GITOPS" ]; then
  grep -rlE 'YOUR''_GH_USER|<GH_USER>|github\.com/GH''_USER/|__AWS_ACCOUNT_ID__' "$GITOPS/argocd" "$GITOPS/argocd-addons" "$GITOPS/envs" >/dev/null 2>&1 \
    && bad "roboshop-gitops still has personal placeholders (GitHub user / account id)" "kit/apply-kit.sh did not finish - re-run it" || ok "roboshop-gitops personalized"
  grep -rnE 'targetRevision: *([0-9]*[xX]\.|X\.Y|v1\.x)' "$GITOPS/argocd" "$GITOPS/argocd-addons" >/dev/null && bad "unpinned targetRevision in roboshop-gitops" "scripts/ft-pin-versions.sh" || ok "Argo CD targetRevisions pinned"
  nb=$(grep -l 'not-built-yet' "$GITOPS"/envs/*/*.yaml 2>/dev/null | wc -l)
  [ "$nb" -eq 0 ] && ok "all envs/*/*.yaml point at built images" || warn "$nb env files still say 'not-built-yet' (fine before golden-setup step G; pods will ImagePullBackOff)"
else warn "no $GITOPS next to roboshop-infra"; fi
GHU=$(grep -E '^gh_user' terraform/20-workstation/terraform.tfvars | cut -d'"' -f2)
[ -n "$GHU" ] && [ "$GHU" != Srinualajangi ] && ok "20-workstation gh_user = $GHU" || bad "gh_user not set" "terraform/20-workstation/terraform.tfvars"
for r in roboshop-infra roboshop-gitops roboshop-app; do
  git ls-remote "https://github.com/$GHU/$r.git" HEAD >/dev/null 2>&1 && ok "github.com/$GHU/$r is public + readable" \
    || bad "github.com/$GHU/$r not readable anonymously" "create it PUBLIC and publish main (the workstation + Argo CD clone without credentials)"
done
lr=$(git rev-parse HEAD 2>/dev/null); rr=$(git ls-remote "https://github.com/$GHU/roboshop-infra.git" refs/heads/main 2>/dev/null | cut -f1)
[ -n "$lr" ] && [ "$lr" = "$rr" ] && ok "roboshop-infra main on GitHub == your local HEAD (the workstation boots what you see)" \
  || warn "local roboshop-infra HEAD differs from GitHub main - the workstation boots GitHub's version"
grep -q 'roboshop.test' /etc/hosts 2>/dev/null && ok "hosts file has *.roboshop.test" || warn "add the *.roboshop.test line to your hosts file (Windows: C:\\Windows\\System32\\drivers\\etc\\hosts)"

echo
echo "== $P ok, $W warnings, $F failed"
[ "$F" -eq 0 ] && echo "✅ ready:  make timed-up" || { echo "❌ fix the ✘ lines first"; exit 1; }
