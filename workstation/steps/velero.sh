#!/usr/bin/env bash
# Day 109: install Velero (S3 backups via the instance role) into today's cluster. Idempotent.
set -euo pipefail
source "$INFRA_DIR/workstation/versions.env"
if ! kubectl -n velero get deploy velero >/dev/null 2>&1; then
  kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace velero pod-security.kubernetes.io/enforce=privileged --overwrite   # node-agent needs hostPath
  velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:${VELERO_AWS_PLUGIN_VERSION} \
    --bucket roboshop-velero-${AWS_ACCOUNT_ID} \
    --backup-location-config region=us-east-1 \
    --use-volume-snapshots=false \
    --no-secret \
    --use-node-agent \
    --wait
fi
velero backup-location get
