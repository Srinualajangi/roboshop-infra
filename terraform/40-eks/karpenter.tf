# roboshop-infra/terraform/40-eks/karpenter.tf
# Creates: controller IAM role (Pod Identity association kube-system/karpenter), node IAM role + EKS access entry,
# SQS interruption queue + EventBridge rules (Spot interruption, rebalance, state changes).
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"
  count   = var.enable_karpenter ? 1 : 0

  cluster_name                    = module.eks.cluster_name
  create_pod_identity_association = true
  namespace                       = "kube-system"
  service_account                 = "karpenter"

  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${local.name}-karpenter-node"
}

output "karpenter_queue_name" { value = var.enable_karpenter ? module.karpenter[0].queue_name : "" }
output "karpenter_node_role" { value = var.enable_karpenter ? module.karpenter[0].node_iam_role_name : "" }
