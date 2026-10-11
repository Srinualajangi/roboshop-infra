# github-oidc.tf — lets GitHub Actions jobs assume AWS roles with short-lived tokens. No static keys.

variable "gh_user" {
  description = "Your personal GitHub username (owner of the roboshop-* repos)"
  type        = string
}

# One OIDC identity provider per AWS account for GitHub.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list is optional in recent AWS providers: AWS validates GitHub's certificate itself.
}

# ---- Role used by roboshop-app CI on main: push images to roboshop/* only ----
data "aws_iam_policy_document" "gha_ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # THE security boundary: only main of roboshop-app. Branches, PRs, forks, other repos: refused.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.gh_user}/roboshop-app:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "gha_ci" {
  name                 = "roboshop-gha-ci"
  description          = "GitHub Actions CI for roboshop-app (main only): push to roboshop/* ECR"
  assume_role_policy   = data.aws_iam_policy_document.gha_ci_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "gha_ci" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this API has no resource-level permissions
  }
  statement {
    sid = "PushPullRoboshopRepos"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
      "ecr:DescribeImages", "ecr:DescribeRepositories", "ecr:ListImages",
    ]
    resources = ["arn:aws:ecr:us-east-1:${data.aws_caller_identity.me.account_id}:repository/roboshop/*"]
  }
}

resource "aws_iam_role_policy" "gha_ci" {
  name   = "ecr-push-roboshop"
  role   = aws_iam_role.gha_ci.id
  policy = data.aws_iam_policy_document.gha_ci.json
}

output "gha_ci_role_arn" {
  value = aws_iam_role.gha_ci.arn
}
