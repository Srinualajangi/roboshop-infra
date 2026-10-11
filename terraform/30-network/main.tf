# roboshop-infra/terraform/30-network/main.tf
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    key          = "30-network/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = "roboshop"
      Environment = "eks-sprint"
      ManagedBy   = "terraform"
      Layer       = "30-network"
    }
  }
}

variable "enable_flow_logs" {
  type    = bool
  default = false
}

module "vpc" {
  source             = "../modules/vpc"
  name               = "roboshop"
  cidr               = "10.40.0.0/16"
  azs                = ["us-east-1a", "us-east-1b"]
  enable_nat_gateway = true
  single_nat_gateway = true # lab: one NAT ($0.045/h). prod: false (one per AZ)
  cluster_name       = "roboshop-eks"
  enable_flow_logs   = var.enable_flow_logs
}

output "vpc_id" { value = module.vpc.vpc_id }
output "vpc_cidr" { value = module.vpc.vpc_cidr }
output "public_subnet_ids" { value = module.vpc.public_subnet_ids }
output "private_app_subnet_ids" { value = module.vpc.private_app_subnet_ids }
output "private_data_subnet_ids" { value = module.vpc.private_data_subnet_ids }
output "app_cidrs" { value = module.vpc.app_cidrs }
output "nat_public_ips" { value = module.vpc.nat_public_ips }
