#!/usr/bin/env bash
# Namespaces for the three environments + ECR pull secret in each (token valid 12h).
set -euo pipefail
bash "$INFRA_DIR/scripts/ecr-pull-secret.sh" roboshop-dev roboshop-qa roboshop-prod
kubectl get ns -l kubernetes.io/metadata.name --no-headers | awk '{print $1}' | grep roboshop
