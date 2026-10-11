#!/usr/bin/env bash
# fast-track kit: one-time prep for the EKS express session (laptop; needs helm, jq, curl).
# Writes terraform/40-eks/addons.env and terraform/40-eks/policies/lbc-iam-policy.json (both committed).
# The IAM policy MUST match the controller version you install, so it is downloaded from that exact tag.
set -euo pipefail
cd "$(dirname "$0")/.."
ENV=terraform/40-eks/addons.env
mkdir -p terraform/40-eks/policies
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update eks external-secrets >/dev/null
read -r LBC_CHART_VERSION LBC_VERSION <<<"$(helm search repo eks/aws-load-balancer-controller -o json | jq -r '.[0] | "\(.version) \(.app_version)"')"
ESO_CHART_VERSION=${ESO_CHART_VERSION:-$(grep -E 'targetRevision' ../roboshop-gitops/argocd/platform/15-external-secrets.yaml 2>/dev/null | awk '{print $2}' | head -1)}
[ -n "$ESO_CHART_VERSION" ] || ESO_CHART_VERSION=$(helm search repo external-secrets/external-secrets -o json | jq -r '.[0].version')
[[ "$LBC_VERSION" == v* ]] || LBC_VERSION="v$LBC_VERSION"
curl -fsSL -o terraform/40-eks/policies/lbc-iam-policy.json \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json"
cat > "$ENV" <<EOF
# terraform/40-eks/addons.env - read by scripts/eks-addons.sh (fast-track kit, written by scripts/ft-eks-prep.sh)
EKS_ADDONS="gp3 lbc eso app"     # express path. Guide extras (Days 103-107): argocd karpenter external-dns
LBC_VERSION=$LBC_VERSION
LBC_CHART_VERSION=$LBC_CHART_VERSION
ESO_CHART_VERSION=$ESO_CHART_VERSION   # same version as the kind lab (argocd/platform/15-external-secrets.yaml)
EOF
echo "wrote $ENV:"; grep -v '^#' "$ENV"
echo "policy statements: $(jq '.Statement | length' terraform/40-eks/policies/lbc-iam-policy.json)"
echo
echo "EKS versions in STANDARD support right now (pick the second-newest, Day 98):"
aws eks describe-cluster-versions --query 'clusterVersions[?status==`STANDARD_SUPPORT`].clusterVersion' --output text 2>/dev/null \
  || echo "  (could not list - aws sso login?)"
echo "40-eks default: $(grep -A3 'variable "kubernetes_version"' terraform/40-eks/variables.tf | grep default | awk -F'"' '{print $2}')"
echo "  -> to change it: echo 'kubernetes_version = \"1.xx\"' >> terraform/40-eks/terraform.tfvars"
echo "Next: commit addons.env, policies/ and tfvars, then  make eks-up"
