# terraform/10-foundation/ecr.tf
locals {
  images = ["web", "catalogue", "user", "cart", "shipping", "payment", "ratings", "dispatch", "mongodb", "mysql"]
}

resource "aws_ecr_repository" "svc" {
  for_each             = toset(local.images)
  name                 = "roboshop/${each.key}"
  image_tag_mutability = "IMMUTABLE" # a tag can never be overwritten
  force_delete         = true        # lab convenience: allows deleting a repo that still has images
  image_scanning_configuration {
    scan_on_push = true # free basic scanning
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "svc" {
  for_each   = aws_ecr_repository.svc
  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 3 days"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 3 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the newest 15 images"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 15 }
        action       = { type = "expire" }
      }
    ]
  })
}

output "ecr_registry" {
  value = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
}
