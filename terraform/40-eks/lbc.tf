# fast-track kit: Day 100 AWS Load Balancer Controller role (the guide appended this to pod-identity.tf;
# the extractor dropped it). policies/lbc-iam-policy.json is downloaded by scripts/ft-eks-prep.sh.
resource "aws_iam_policy" "lbc" {
  name   = "${local.name}-lbc"
  policy = file("${path.module}/policies/lbc-iam-policy.json")
}

resource "aws_iam_role" "lbc" {
  name               = "${local.name}-lbc"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

# "Pods using ServiceAccount kube-system/aws-load-balancer-controller get this role"
resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn
}
