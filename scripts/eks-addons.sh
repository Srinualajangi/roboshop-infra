#!/usr/bin/env bash
# Installs in-cluster add-ons on the EKS sprint cluster. Driven by EKS_ADDONS in terraform/40-eks/addons.env.
# fast-track kit: the gp3/lbc/eso/app cases from Days 100-101 assembled into one file. Fix vs the guide:
# "app" installs EVERY prod service (envs/prod/_common.yaml + envs/prod/<svc>.yaml + envs-eks overlays),
# not only the two services that have an envs-eks/prod file.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source terraform/40-eks/addons.env
CLUSTER=$(terraform -chdir=terraform/40-eks output -raw cluster_name)
VPC_ID=$(terraform -chdir=terraform/40-eks output -raw vpc_id)
MYIP=$(curl -fsS https://checkip.amazonaws.com)
GITOPS=${GITOPS:-$HOME/roboshop/roboshop-gitops}
kubectl config use-context roboshop-eks >/dev/null
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update eks external-secrets >/dev/null
for a in $EKS_ADDONS; do
  echo "=== add-on: $a ==="
  case "$a" in
    gp3)  # EBS gp3 as the default StorageClass (StatefulSets: mongodb, mysql, redis, rabbitmq)
      kubectl apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer   # create the volume in the AZ where the pod lands
reclaimPolicy: Delete
allowVolumeExpansion: true
parameters:
  type: gp3
  encrypted: "true"
YAML
      kubectl annotate sc gp2 storageclass.kubernetes.io/is-default-class=false --overwrite 2>/dev/null || true
      ;;
    lbc)  # AWS Load Balancer Controller. Region + VPC passed explicitly because pods cannot reach IMDS (hop limit 1)
      helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        --version "$LBC_CHART_VERSION" -n kube-system \
        --set clusterName="$CLUSTER" --set region=us-east-1 --set vpcId="$VPC_ID" \
        --set serviceAccount.create=true --set serviceAccount.name=aws-load-balancer-controller \
        --wait --timeout 5m
      ;;
    eso)  # External Secrets Operator using its own Pod Identity role (no static keys, no node role)
      helm upgrade --install external-secrets external-secrets/external-secrets \
        --version "$ESO_CHART_VERSION" -n external-secrets --create-namespace --wait --timeout 5m
      for i in $(seq 1 12); do
        kubectl apply -f - <<'YAML' && break || { echo "ESO webhook not ready yet, retry $i/12"; sleep 10; }
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-ssm
spec:
  provider:
    aws:
      service: ParameterStore
      region: us-east-1
      # no auth block: the SDK default chain picks up Pod Identity credentials
YAML
      done
      ;;
    app)  # RoboShop prod from the gitops repo + EKS overlay, and the Ingress (ALB) restricted to your IP
      EP=$(terraform -chdir=terraform/50-data output -raw db_endpoint 2>/dev/null || true)   # RDS only if you applied 50-data
      for f in "$GITOPS"/envs/prod/*.yaml; do
        svc=$(basename "$f" .yaml); [ "$svc" = _common ] && continue
        extra=()
        if [ -f "$GITOPS/envs-eks/prod/$svc.yaml" ] && [ -n "$EP" ]; then
          extra=(-f <(EP="$EP" envsubst < "$GITOPS/envs-eks/prod/$svc.yaml"))
        fi
        echo "   helm $svc"
        helm upgrade --install "$svc" "$GITOPS/charts/roboshop-service" -n roboshop-prod --create-namespace \
          -f "$GITOPS/envs/prod/_common.yaml" -f "$f" -f "$GITOPS/envs-eks/common.yaml" ${extra[@]+"${extra[@]}"}   # (safe with set -u on old bash)
      done
      MYIP="$MYIP" envsubst < "$GITOPS/envs-eks/manifests/ingress-web.yaml" | kubectl apply -f -
      echo "   ALB (takes ~2-3 min): kubectl -n roboshop-prod get ingress web -w"
      ;;
    *) echo "unknown add-on $a (express kit supports: gp3 lbc eso app; see the guide Days 103-107 for more)"; exit 1 ;;
  esac
done
echo "add-ons done: $EKS_ADDONS"
