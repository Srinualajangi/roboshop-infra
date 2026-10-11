# ---------- CloudTrail: management events -> our own S3 bucket ----------
resource "aws_s3_bucket" "trail" {
  bucket = "roboshop-cloudtrail-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    id     = "expire-after-180-days"
    status = "Enabled"
    filter {}
    expiration {
      days = 180
    }
  }
}

locals {
  trail_name = "roboshop-trail"
  trail_arn  = "arn:aws:cloudtrail:us-east-1:${local.account_id}:trail/${local.trail_name}"
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true   # catches activity in regions you never use (a classic attacker trick)
  include_global_service_events = true   # IAM, STS, CloudFront events
  enable_log_file_validation    = true   # digest files prove logs were not altered
  depends_on                    = [aws_s3_bucket_policy.trail]
}

# ---------- IAM Access Analyzer: external access (free) ----------
resource "aws_accessanalyzer_analyzer" "external" {
  analyzer_name = "roboshop-external-access"
  type          = "ACCOUNT"
}

# Unused-access analyzer is PAID (per role/user analysed per month). Uncomment only if you accept the cost.
# resource "aws_accessanalyzer_analyzer" "unused" {
#   analyzer_name = "roboshop-unused-access"
#   type          = "ACCOUNT_UNUSED_ACCESS"
#   configuration {
#     unused_access {
#       unused_access_age = 90
#     }
#   }
# }
