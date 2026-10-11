#!/usr/bin/env bash
# Delete AWS resources that Kubernetes controllers created (ALBs, NLBs, EBS volumes, Karpenter nodes)
# BEFORE Terraform destroys the cluster. Otherwise they are orphaned, keep billing and block VPC deletion.
set -uo pipefail
k() { kubectl --context roboshop-eks "$@"; }
if ! k get nodes >/dev/null 2>&1; then echo "EKS not reachable - nothing to clean"; exit 0; fi

echo "1/5 Argo CD apps (so it does not recreate what we delete)"
k -n argocd delete applications.argoproj.io,applicationsets.argoproj.io --all --wait=false 2>/dev/null || true

echo "2/5 Ingresses -> ALBs"
k delete ingress --all -A --wait=false
echo "3/5 Services of type LoadBalancer -> NLB/CLB"
k get svc -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' |
  while read -r ns name; do k -n "$ns" delete svc "$name" --wait=false; done

echo "4/5 Karpenter NodePools -> EC2 instances it launched"
k delete nodepools.karpenter.sh --all 2>/dev/null || true

echo "5/5 PVCs -> EBS volumes (delete app namespaces)"
for ns in $(k get ns -o name | grep -E 'roboshop-' | cut -d/ -f2); do k delete ns "$ns" --timeout=5m; done
k delete pvc --all -A --timeout=3m 2>/dev/null || true

echo "waiting 90s for controllers to delete load balancers..."
sleep 90
left=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName,'k8s-')].LoadBalancerName" --output text)
[ -n "$left" ] && echo "WARNING still present: $left (delete in console/CLI if destroy fails)" || echo "load balancers gone"
