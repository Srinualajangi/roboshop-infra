#!/usr/bin/env bash
# Installs Argo CD (pinned chart) — the only thing besides the cluster that is NOT managed by GitOps.
set -euo pipefail
source "$INFRA_DIR/workstation/versions.env"
GITOPS=~/work/roboshop-gitops

echo ">> argocd: chart $ARGOCD_CHART_VERSION"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version "$ARGOCD_CHART_VERSION" \
  -f "$GITOPS/platform/argocd/values.yaml" \
  --wait --timeout 10m

if kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then
  kubectl apply -f "$GITOPS/platform/argocd/route/"
fi

# Let tools ON the workstation resolve the lab hostnames to Traefik (host port 80).
if ! grep -q 'argocd.roboshop.test' /etc/hosts; then
  echo "127.0.0.1 argocd.roboshop.test dev.roboshop.test qa.roboshop.test prod.roboshop.test grafana.roboshop.test prometheus.roboshop.test alertmanager.roboshop.test jenkins.roboshop.test sonar.roboshop.test rollouts.roboshop.test" \
    | sudo tee -a /etc/hosts >/dev/null
fi
echo ">> argocd: ready"
