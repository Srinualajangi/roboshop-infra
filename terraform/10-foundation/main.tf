# terraform/10-foundation/main.tf
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    key          = "10-foundation/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project   = "roboshop"
      ManagedBy = "terraform"
      Layer     = "10-foundation"
      Owner     = var.owner
    }
  }
}

data "aws_caller_identity" "me" {}

locals {
  account_id = data.aws_caller_identity.me.account_id
  region     = "us-east-1"
}

variable "owner" {
  type        = string
  description = "Your name, used in tags"
}

variable "alert_email" {
  type        = string
  description = "Where budget alerts go"
}

variable "monthly_budget_usd" {
  type    = number
  default = 25
}
