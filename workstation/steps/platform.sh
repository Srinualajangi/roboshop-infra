#!/usr/bin/env bash
# Cluster add-ons installed at boot until Argo CD manages them (Phase 5):
# Gateway API CRDs, Traefik, metrics-server, and namespace/RBAC policy files from roboshop-gitops/platform.
set -euo pipefail
source "$INFRA_DIR/workstation/versions.env"
P="$HOME/work/roboshop-gitops/platform"
echo "gateway api CRDs $GATEWAY_API_VERSION"
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install traefik traefik/traefik -n traefik --create-namespace \
  --version "$TRAEFIK_CHART_VERSION" -f "$P/traefik/values.yaml"
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system \
  --version "$METRICS_SERVER_CHART_VERSION" -f "$P/metrics-server/values.yaml"
for d in namespaces rbac; do            # added on Days 43 and 46
  if [ -d "$P/$d" ]; then kubectl apply -f "$P/$d/"; fi
done
kubectl -n traefik rollout status deploy/traefik --timeout=180s
echo "platform ready. Deploy apps with:  make -C ~/work/roboshop-gitops deploy-all"
