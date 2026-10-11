# roboshop-infra/terraform/10-foundation/velero.tf
resource "aws_s3_bucket" "velero" {
  bucket        = "roboshop-velero-${local.account_id}"
  force_destroy = true   # lab: lets you delete it with backups inside
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket                  = aws_s3_bucket.velero.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id
  rule {
    id     = "expire-after-14-days"
    status = "Enabled"
    filter {}
    expiration {
      days = 14
    }
  }
}
