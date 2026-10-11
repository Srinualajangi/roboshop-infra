#!/usr/bin/env bash
# Usage: ecr-pull-secret.sh <namespace> [namespace...]
# Creates/refreshes the "ecr-pull" docker-registry secret in each namespace.
# ECR tokens expire after 12 hours: re-run this if pods show ImagePullBackOff with "401" or "no basic auth credentials".
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <namespace>..."; exit 1; }
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
TOKEN="$(aws ecr get-login-password --region "$REGION")"
for ns in "$@"; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$ns" create secret docker-registry ecr-pull \
    --docker-server="$REGISTRY" --docker-username=AWS --docker-password="$TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
done
