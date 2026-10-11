#!/usr/bin/env bash
# fast-track kit: pin EVERY version the lab uses, in one go, on the LAPTOP (needs: curl jq yq(v4) helm; bash 3.2+ ok).
#   * workstation/versions.env          tool versions + chart versions used by boot steps
#   * roboshop-gitops Argo CD apps      every Helm-chart source "targetRevision" (+ the Gateway API git tag)
# Only placeholders (x.y.z, X.Y.Z, 3x.y.z, PIN_ME, <...>) and lines marked "# example" are replaced, so re-running
# never moves a version you already pinned. FORCE=1 re-pins everything to "latest" (deliberately; then test + commit).
# Tip: export GITHUB_TOKEN=<read-only token> to avoid GitHub's 60 requests/hour anonymous API limit.
set -euo pipefail
cd "$(dirname "$0")/.."
GITOPS=${GITOPS:-../roboshop-gitops}
VE=workstation/versions.env
for t in curl jq yq helm; do command -v $t >/dev/null || { echo "missing '$t' on the laptop (01-golden-setup.md step A3)"; exit 1; }; done
yq --version 2>&1 | grep -q 'mikefarah' || { echo "yq must be mikefarah/yq v4 (not the python yq)"; exit 1; }
[ -d "$GITOPS/argocd" ] || { echo "roboshop-gitops not found at $GITOPS (set GITOPS=...)"; exit 1; }
TODAY=$(date +%F)

is_placeholder() { [ "${FORCE:-0}" = 1 ] || [ -z "$1" ] || echo "$1" | grep -qE 'PIN_ME|<|[0-9][xXz]|(^|[.v])[xXyYzZw](\.|$)'; }
gh_latest() {   # API first; if rate-limited/blocked, follow the public "releases/latest" redirect (no API quota)
  curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
    | jq -r .tag_name 2>/dev/null | grep -v '^null$' \
  || curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" 2>/dev/null | sed -n 's#.*/releases/tag/##p'
}
setv() {   # setv KEY VALUE  -> versions.env (only replaces placeholders / "# example" lines)
  local line cur
  [ -n "$2" ] && [ "$2" != null ] || { echo "  ! $1: could not resolve a version (rate limit? set GITHUB_TOKEN)"; return; }
  line=$(grep -E "^$1=" "$VE" | head -1 || true)
  if [ -n "$line" ]; then
    cur=$(echo "$line" | cut -d= -f2- | awk '{print $1}' | tr -d '"')
    if ! is_placeholder "$cur" && ! echo "$line" | grep -q '# *example'; then printf '  = %-28s %s (kept)\n' "$1" "$cur"; return; fi
    sed -i.bak -E "s|^$1=.*|$1=$2   # pinned $TODAY by ft-pin-versions.sh|" "$VE" && rm -f "$VE.bak"
  else
    echo "$1=$2   # pinned $TODAY by ft-pin-versions.sh" >> "$VE"
  fi
  printf '  + %-28s %s\n' "$1" "$2"
}
chart_latest() {   # chart_latest <repoURL> <chart>  -> "version appVersion"
  local url=${1%/} alias
  alias="ft-$(echo "$url" | sed -E 's#^https?://##; s#[^A-Za-z0-9]+#-#g' | cut -c1-40)"
  helm repo list 2>/dev/null | awk '{print $1}' | grep -qx "$alias" || helm repo add "$alias" "$url" >/dev/null
  helm repo update "$alias" >/dev/null 2>&1 || true
  helm search repo "$alias/$2" -o json | jq -r --arg n "$alias/$2" '.[] | select(.name==$n) | "\(.version) \(.app_version)"' | head -1
}

echo "== CLI tools -> $VE"
setv KUBECTL_VERSION   "$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
setv KIND_VERSION      "$(gh_latest kubernetes-sigs/kind)"
setv HELM_VERSION      "$(gh_latest helm/helm)"
setv K9S_VERSION       "$(gh_latest derailed/k9s)"
setv YQ_VERSION        "$(gh_latest mikefarah/yq)"
setv TRIVY_VERSION     "$(gh_latest aquasecurity/trivy | sed 's/^v//')"
setv TERRAFORM_VERSION "$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)"
setv COSIGN_VERSION    "$(gh_latest sigstore/cosign)"
setv HADOLINT_VERSION  "$(gh_latest hadolint/hadolint)"
setv PLUTO_VERSION     "$(gh_latest FairwindsOps/pluto)"
setv VELERO_VERSION    "$(gh_latest vmware-tanzu/velero)"
setv VELERO_AWS_PLUGIN_VERSION "$(gh_latest vmware-tanzu/velero-plugin-for-aws)"
setv CALICO_VERSION    "$(gh_latest projectcalico/calico)"
setv GATEWAY_API_VERSION "${GATEWAY_API_VERSION:-$(gh_latest kubernetes-sigs/gateway-api)}"
# kind uses the node image built for its own release when KIND_NODE_IMAGE is empty: simplest and always compatible
if grep -E '^KIND_NODE_IMAGE=' "$VE" | grep -qE 'z\.w|<'; then
  sed -i.bak -E 's|^KIND_NODE_IMAGE=.*|KIND_NODE_IMAGE=""   # empty = default node image of the pinned kind release|' "$VE" && rm -f "$VE.bak"
  echo "  + KIND_NODE_IMAGE              \"\" (kind default)"
fi

echo "== Helm charts used by boot steps -> $VE"
read -r v app <<<"$(chart_latest https://argoproj.github.io/argo-helm argo-cd)";       setv ARGOCD_CHART_VERSION "$v";   setv ARGOCD_VERSION "$app"
read -r v app <<<"$(chart_latest https://argoproj.github.io/argo-helm argo-rollouts)"; setv ROLLOUTS_CHART_VERSION "$v"; setv ROLLOUTS_VERSION "$app"
read -r v _ <<<"$(chart_latest https://traefik.github.io/charts traefik)";                         setv TRAEFIK_CHART_VERSION "$v"
read -r v _ <<<"$(chart_latest https://kubernetes-sigs.github.io/metrics-server metrics-server)";  setv METRICS_SERVER_CHART_VERSION "$v"
read -r v _ <<<"$(chart_latest https://prometheus-community.github.io/helm-charts kube-prometheus-stack)";    setv KPS_CHART_VERSION "$v"
read -r v _ <<<"$(chart_latest https://prometheus-community.github.io/helm-charts prometheus-operator-crds)"; setv PROM_CRDS_CHART_VERSION "$v"
vget() { grep -E "^$1=" "$VE" | head -1 | cut -d= -f2- | awk '{print $1}' | tr -d '"'; }

echo "== Argo CD Applications in $GITOPS (targetRevision of every chart source)"
for f in "$GITOPS"/argocd/platform/*.yaml "$GITOPS"/argocd-addons/*/*.yaml; do
  [ -f "$f" ] || continue
  if [ "$(yq '.spec | has("sources")' "$f")" = true ]; then paths=$(yq '.spec.sources | keys | .[]' "$f" | sed 's/^/.spec.sources[/; s/$/]/')
  else paths=.spec.source; fi
  for p in $paths; do
    url=$(yq "$p.repoURL" "$f"); chart=$(yq "$p.chart // \"\"" "$f"); cur=$(yq "$p.targetRevision" "$f")
    case "$chart" in   # keep Argo CD apps and boot steps on the SAME versions where both exist
      argo-rollouts) want=$(vget ROLLOUTS_CHART_VERSION);;   traefik) want=$(vget TRAEFIK_CHART_VERSION);;
      metrics-server) want=$(vget METRICS_SERVER_CHART_VERSION);; kube-prometheus-stack) want=$(vget KPS_CHART_VERSION);;
      prometheus-operator-crds) want=$(vget PROM_CRDS_CHART_VERSION);;
      "") if echo "$url" | grep -q 'kubernetes-sigs/gateway-api'; then chart=gateway-api-crds; want=$(vget GATEWAY_API_VERSION); else continue; fi;;
      *) want=$(chart_latest "$url" "$chart" | awk '{print $1}');;
    esac
    if [ -z "$want" ] || [ "$want" = null ] || { [ "${FORCE:-0}" != 1 ] && is_placeholder "$want"; }; then
      echo "  ! $(basename "$f"): could not resolve $chart (from $url) - left as is"; continue; fi
    if is_placeholder "$cur"; then
      W="$want" C="pinned $TODAY by ft-pin-versions.sh" yq -i "$p.targetRevision = strenv(W) | ($p.targetRevision | line_comment) = strenv(C)" "$f"
      printf '  + %-36s %-26s %s\n' "$(basename "$f")" "$chart" "$want"
    else
      printf '  = %-36s %-26s %s (kept)\n' "$(basename "$f")" "$chart" "$cur"
    fi
  done
done

echo
bad=0
while IFS= read -r l; do v=$(echo "$l" | cut -d= -f2- | awk '{print $1}' | tr -d '"'); [ -z "$v" ] && continue
  is_placeholder "$v" && [ "${FORCE:-0}" != 1 ] && { echo "  ⚠️  versions.env: $l"; bad=1; }; done < <(grep -E '^[A-Z_]+=' "$VE" | grep -v '^KIND_NODE_IMAGE=')
for f in "$GITOPS"/argocd/platform/*.yaml "$GITOPS"/argocd-addons/*/*.yaml; do
  for v in $(yq '.. | select(has("targetRevision")) | .targetRevision' "$f" 2>/dev/null); do
    [ "$v" = main ] || { is_placeholder "$v" && [ "${FORCE:-0}" != 1 ] && { echo "  ⚠️  $(basename "$f"): targetRevision $v"; bad=1; }; } || true
  done
done
[ "$bad" = 0 ] || { echo "Some versions are still placeholders (see above). Fix them by hand or re-run with GITHUB_TOKEN set."; exit 1; }
echo "✅ everything pinned. Review: git diff --stat ; git -C $GITOPS diff --stat"
echo "   2-minute compatibility check (chart schemas move between majors):"
echo "   helm show values ft-traefik-github-io-charts/traefik --version $(vget TRAEFIK_CHART_VERSION) | yq '.gateway.listeners.web, .ports.web'"
echo "   -> roboshop-gitops/platform/traefik/values.yaml sets gateway.listeners.web.namespacePolicy and ports.web.nodePort"
