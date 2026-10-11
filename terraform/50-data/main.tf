# roboshop-infra/terraform/50-data/main.tf
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    key          = "50-data/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { Project = "roboshop", Environment = "eks-sprint", ManagedBy = "terraform", Layer = "50-data" }
  }
}

variable "mysql_version" {
  type    = string
  default = "8.4.6" # example — use what Step 1 printed
}

data "aws_caller_identity" "me" {}

locals {
  bucket = "roboshop-tfstate-${data.aws_caller_identity.me.account_id}"
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config  = { bucket = local.bucket, key = "30-network/terraform.tfstate", region = "us-east-1" }
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config  = { bucket = local.bucket, key = "40-eks/terraform.tfstate", region = "us-east-1" }
}

resource "aws_db_subnet_group" "mysql" {
  name       = "roboshop-data"
  subnet_ids = data.terraform_remote_state.network.outputs.private_data_subnet_ids # no internet route
}

resource "aws_security_group" "mysql" {
  name        = "roboshop-rds-mysql"
  description = "MySQL from EKS nodes only"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "from_nodes" {
  security_group_id            = aws_security_group.mysql.id
  referenced_security_group_id = data.terraform_remote_state.eks.outputs.node_security_group_id # SG-to-SG
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = "EKS nodes (pods use the node ENIs' security groups)"
}

resource "aws_db_instance" "mysql" {
  identifier     = "roboshop-mysql"
  engine         = "mysql"
  engine_version = var.mysql_version
  instance_class = "db.t4g.micro" # Graviton, ~$0.016/h

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  username                    = "admin"
  manage_master_user_password = true # RDS creates + stores the password in Secrets Manager; Terraform never sees it

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.mysql.id]
  publicly_accessible    = false
  multi_az               = false # prod: true (synchronous standby in another AZ, automatic failover)

  backup_retention_period = 1     # prod: 7-35 days for point-in-time restore
  skip_final_snapshot     = true  # LAB ONLY. prod: false + final_snapshot_identifier
  deletion_protection     = false # LAB ONLY. prod: true
  apply_immediately       = true
}

output "mysql_endpoint" { value = aws_db_instance.mysql.address }
output "mysql_secret_arn" { value = aws_db_instance.mysql.master_user_secret[0].secret_arn }
