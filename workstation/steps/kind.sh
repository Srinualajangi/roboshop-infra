#!/usr/bin/env bash
# Creates the "roboshop" kind cluster (1 control-plane + 3 workers). Idempotent.
set -euo pipefail
CFG="$INFRA_DIR/workstation/kind/cluster.yaml"
if kind get clusters 2>/dev/null | grep -qx roboshop; then
  echo "kind cluster 'roboshop' already exists - skipping"
else
  echo "creating kind cluster 'roboshop' from $CFG"
  kind create cluster --name roboshop --config "$INFRA_DIR/workstation/kind/cluster.yaml" ${KIND_NODE_IMAGE:+--image "$KIND_NODE_IMAGE"} --wait 120s
fi
kubectl config use-context kind-roboshop
kubectl get nodes -o wide
