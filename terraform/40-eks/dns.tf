# roboshop-infra/terraform/40-eks/dns.tf  — Day 107 (optional; needs a domain)
variable "domain_name" {
  description = "Your registered domain, e.g. example.com. Empty = skip DNS/TLS."
  type        = string
  default     = ""
}

locals { dns = var.domain_name != "" }

data "aws_route53_zone" "this" {
  count = local.dns ? 1 : 0
  name  = var.domain_name
}

resource "aws_acm_certificate" "shop" {
  count                     = local.dns ? 1 : 0
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.dns ? {
    for o in aws_acm_certificate.shop[0].domain_validation_options : o.domain_name => o
  } : {}
  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true # apex and wildcard share the same validation record
}

resource "aws_acm_certificate_validation" "shop" {
  count                   = local.dns ? 1 : 0
  certificate_arn         = aws_acm_certificate.shop[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_iam_role" "external_dns" {
  count              = local.dns ? 1 : 0
  name               = "${local.name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "external_dns" {
  count = local.dns ? 1 : 0
  role  = aws_iam_role.external_dns[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["route53:ChangeResourceRecordSets"], Resource = data.aws_route53_zone.this[0].arn },
      { Effect = "Allow", Action = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResources"], Resource = "*" }
    ]
  })
}

resource "aws_eks_pod_identity_association" "external_dns" {
  count           = local.dns ? 1 : 0
  cluster_name    = module.eks.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns[0].arn
}

output "certificate_arn" { value = local.dns ? aws_acm_certificate_validation.shop[0].certificate_arn : "" }
output "domain_name" { value = var.domain_name }
