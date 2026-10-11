# terraform/10-foundation/iam-workstation.tf
# The daily workstation (and, through IMDS, pods inside its kind cluster) use this role.
# Keep it least-privilege: later phases ADD statements here deliberately.
resource "aws_iam_role" "workstation" {
  name = "roboshop-workstation"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Lets the SSM agent register the instance -> Session Manager shell/tunnels with no SSH port
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.workstation.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "workstation" {
  name = "roboshop-workstation"
  role = aws_iam_role.workstation.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # this API does not support resource-level permissions
      },
      {
        Sid    = "EcrRoboshopRepos"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages", "ecr:DescribeRepositories", "ecr:ListImages", "ecr:DescribeImageScanFindings",
          "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"
        ]
        Resource = "arn:aws:ecr:${local.region}:${local.account_id}:repository/roboshop/*"
      },
      {
        Sid      = "ReadRoboshopParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/roboshop/*"
      },
      {
        Sid      = "WriteLabStatus"
        Effect   = "Allow"
        Action   = ["ssm:PutParameter"]
        Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/roboshop/lab/*"
      },
      { # Day 71 (fast-track kit: was missing) - sonar-setup.sh stores the Jenkins token
        Sid      = "WriteSonarToken"
        Effect   = "Allow"
        Action   = ["ssm:PutParameter"]
        Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/roboshop/ci/sonar-token"
      },
      { # Day 109 (fast-track kit: was missing) - Velero backups from the kind cluster
        Sid    = "VeleroBucket"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = ["arn:aws:s3:::roboshop-velero-${local.account_id}",
        "arn:aws:s3:::roboshop-velero-${local.account_id}/*"]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "workstation" {
  name = "roboshop-workstation"
  role = aws_iam_role.workstation.name
}

output "workstation_instance_profile" {
  value = aws_iam_instance_profile.workstation.name
}
