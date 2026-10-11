# .tflint.hcl — pin the AWS ruleset (latest: github.com/terraform-linters/tflint-ruleset-aws/releases)
plugin "aws" {
  enabled = true
  version = "0.0.0" # ← pin the release you found (no leading v)
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
