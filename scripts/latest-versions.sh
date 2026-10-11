#!/usr/bin/env bash
# Prints the latest release of every tool and chart this project pins.
# Usage: scripts/latest-versions.sh          (export GITHUB_TOKEN=... to avoid the 60 req/h API limit)
set -euo pipefail
command -v jq >/dev/null || { echo "needs jq"; exit 1; }

gh_latest() {   # owner/repo -> latest release tag (e.g. v0.30.0)
  curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    "https://api.github.com/repos/$1/releases/latest" | jq -r '.tag_name'
}
hc_latest() {   # HashiCorp product -> latest version (no v)
  curl -fsSL "https://checkpoint-api.hashicorp.com/v1/check/$1" | jq -r '.current_version'
}
row() { printf '%-26s %s\n' "$1" "$2"; }

echo "# ---- CLI tools (paste chosen values into workstation/versions.env) ----"
row KUBECTL_VERSION      "$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
row KIND_VERSION         "$(gh_latest kubernetes-sigs/kind)"
row HELM_VERSION         "$(gh_latest helm/helm)"
row K9S_VERSION          "$(gh_latest derailed/k9s)"
row YQ_VERSION           "$(gh_latest mikefarah/yq)"
row TRIVY_VERSION        "$(gh_latest aquasecurity/trivy | sed 's/^v//')"
row ARGOCD_VERSION       "$(gh_latest argoproj/argo-cd)"
row TERRAFORM_VERSION    "$(hc_latest terraform)"
row PACKER_VERSION       "$(hc_latest packer)"
row GATEWAY_API_VERSION  "$(gh_latest kubernetes-sigs/gateway-api)"
row ROLLOUTS_VERSION     "$(gh_latest argoproj/argo-rollouts)"
row VELERO_VERSION       "$(gh_latest vmware-tanzu/velero)"
row COSIGN_VERSION       "$(gh_latest sigstore/cosign)"
row HADOLINT_VERSION     "$(gh_latest hadolint/hadolint)"

echo
echo "# ---- Helm charts (use as targetRevision / *_CHART_VERSION) ----"
if command -v helm >/dev/null; then
  helm repo add argo                 https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm repo add traefik              https://traefik.github.io/charts >/dev/null 2>&1 || true
  helm repo add external-secrets     https://charts.external-secrets.io >/dev/null 2>&1 || true
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add grafana              https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add metrics-server       https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
  helm repo add kyverno              https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
  helm repo add jenkins              https://charts.jenkins.io >/dev/null 2>&1 || true
  helm repo add open-telemetry       https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
  helm repo add aqua                 https://aquasecurity.github.io/helm-charts/ >/dev/null 2>&1 || true
  helm repo add vmware-tanzu         https://vmware-tanzu.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add eks                  https://aws.github.io/eks-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null
  for c in argo/argo-cd argo/argo-rollouts traefik/traefik external-secrets/external-secrets \
           prometheus-community/kube-prometheus-stack grafana/loki grafana/tempo grafana/alloy \
           metrics-server/metrics-server kyverno/kyverno jenkins/jenkins \
           open-telemetry/opentelemetry-operator aqua/trivy-operator vmware-tanzu/velero \
           eks/aws-load-balancer-controller; do
    v=$(helm search repo "$c" -o json | jq -r --arg c "$c" '.[] | select(.name==$c) | "\(.version)  (app \(.app_version))"')
    row "$c" "${v:-not found}"
  done
else
  echo "helm not installed here; run this on the workstation for chart versions"
fi
