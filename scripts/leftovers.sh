#!/usr/bin/env bash
# roboshop-infra/scripts/leftovers.sh - lists anything in the region that is still costing money.
# Safe to run any time (read-only). Exit code is always 0; read the output.
set -uo pipefail
R=${AWS_REGION:-us-east-1}
found=0
show() {   # show "<title>" "<command output>"
  local title=$1 out=$2
  if [ -n "$out" ] && [ "$out" != "None" ]; then
    echo "⚠️  $title"; echo "$out" | sed 's/^/     /'; found=1
  fi
}
show "EC2 instances (pending/running/stopping/stopped)" "$(aws ec2 describe-instances --region "$R" \
  --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`]|[0].Value]' --output text)"
show "NAT gateways" "$(aws ec2 describe-nat-gateways --region "$R" --filter Name=state,Values=pending,available \
  --query 'NatGateways[].[NatGatewayId,VpcId,State]' --output text)"
show "Load balancers (ALB/NLB)" "$(aws elbv2 describe-load-balancers --region "$R" \
  --query 'LoadBalancers[].[LoadBalancerName,Type,State.Code]' --output text)"
show "EKS clusters" "$(aws eks list-clusters --region "$R" --query 'clusters[]' --output text)"
show "RDS instances" "$(aws rds describe-db-instances --region "$R" \
  --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus]' --output text)"
show "Elastic IPs not attached to anything" "$(aws ec2 describe-addresses --region "$R" \
  --query 'Addresses[?AssociationId==null].[PublicIp,AllocationId]' --output text)"
show "Unattached EBS volumes" "$(aws ec2 describe-volumes --region "$R" --filters Name=status,Values=available \
  --query 'Volumes[].[VolumeId,Size,CreateTime]' --output text)"
if [ "$found" -eq 0 ]; then
  echo "✅ Nothing billable left running in $R (persistent S3 state, ECR images and SSM parameters cost cents/month)."
fi
exit 0
