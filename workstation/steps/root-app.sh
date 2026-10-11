#!/usr/bin/env bash
# Hands the cluster to GitOps, then performs the DR "sync everything to Git" for manual-sync envs.
# fast-track kit additions:
#   * LAB_PROFILES (lab.env) adds one Argo CD app per add-on profile (argocd-addons/<profile>), so a
#     broken add-on can never block the core platform or the shop.
#   * waits for the Argo Rollouts CRD before the qa/prod DR sync, and the sync has a retry block.
set -euo pipefail
GITOPS=~/work/roboshop-gitops
# Also safe to run BY HAND on the workstation (re-applies everything, re-syncs qa/prod):
#   bash ~/work/roboshop-infra/workstation/steps/root-app.sh
INFRA_DIR=${INFRA_DIR:-$HOME/work/roboshop-infra}   # by hand: your working clone (sees today's lab.env edits)
GH_USER=${GH_USER:-$(git -C "$GITOPS" remote get-url origin | sed -E 's#.*github.com[:/]([^/]+)/.*#\1#')}
# shellcheck source=/dev/null
source "$INFRA_DIR/workstation/lab.env"
LAB_PROFILES=${LAB_PROFILES_OVERRIDE:-${LAB_PROFILES:-}}   # set by bootstrap.sh (make up-full) - else lab.env
REPO="https://github.com/${GH_USER}/roboshop-gitops.git"

echo ">> root-app: applying argocd/root.yaml (core platform + 3 envs)"
kubectl apply -f "$GITOPS/argocd/root.yaml"

for p in ${LAB_PROFILES:-}; do
  [ -d "$GITOPS/argocd-addons/$p" ] || { echo "   unknown profile '$p' (no argocd-addons/$p) - skipped"; continue; }
  echo ">> root-app: add-on profile '$p'"
  kubectl apply -f - <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: addons-$p
  namespace: argocd
  labels: { roboshop.lab/profile: "$p" }
spec:
  project: default
  source: { repoURL: "$REPO", targetRevision: main, path: "argocd-addons/$p", directory: { recurse: true } }
  destination: { server: https://kubernetes.default.svc, namespace: argocd }
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    retry: { limit: 10, backoff: { duration: 10s, factor: 2, maxDuration: 3m } }
YAML
done

echo ">> root-app: waiting for the ApplicationSet to generate qa/prod apps"
n=0
for i in $(seq 1 60); do
  n=$(kubectl -n argocd get applications -l 'env in (qa,prod)' --no-headers 2>/dev/null | wc -l)
  [ "$n" -gt 0 ] && break
  sleep 10
done
[ "$n" -gt 0 ] || { echo "no qa/prod apps after 10 min - check: kubectl -n argocd get applications"; exit 1; }
sleep 20   # let the generator finish creating the whole set

echo ">> root-app: waiting for the Argo Rollouts CRD (prod catalogue + qa web are Rollouts)"
for i in $(seq 1 60); do kubectl get crd rollouts.argoproj.io >/dev/null 2>&1 && break; sleep 10; done

# Fresh cluster = DR rebuild. qa/prod are manual-sync by design; bring them to the reviewed Git state once.
for app in $(kubectl -n argocd get applications -l 'env in (qa,prod)' -o name); do
  kubectl -n argocd patch "$app" --type merge -p '{"operation":{"initiatedBy":{"username":"bootstrap-dr-rebuild"},
    "sync":{"prune":true,"syncOptions":["ServerSideApply=true"]},
    "retry":{"limit":5,"backoff":{"duration":"20s","factor":2,"maxDuration":"3m"}}}}' >/dev/null
  echo "   sync requested: $app"
done
echo ">> root-app: done (profiles: core ${LAB_PROFILES:-})"
