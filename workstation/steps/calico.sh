#!/usr/bin/env bash
# Calico CNI for kind clusters created with disableDefaultCNI: true. Must run right after "kind".
set -euo pipefail
source "$INFRA_DIR/workstation/versions.env"
kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" 2>/dev/null || true
kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml" 2>/dev/null || true
kubectl wait --for=condition=Ready nodes --all --timeout=300s
