# terraform/20-workstation/main.tf
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    key          = "20-workstation/terraform.tfstate"
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
      Environment = "lab"
      ManagedBy   = "terraform"
      Layer       = "20-workstation"
      Owner       = var.owner
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

# created by 10-foundation
data "aws_iam_instance_profile" "ws" {
  name = "roboshop-workstation"
}

resource "aws_security_group" "ws" {
  name        = "roboshop-workstation"
  description = "RoboShop workstation - NO inbound rules. Access is via SSM Session Manager only."
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Outbound for package installs, image pulls and the SSM agent"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "roboshop-workstation"
  }
}

resource "aws_instance" "ws" {
  ami                                  = var.ami_id
  instance_type                        = var.instance_type
  subnet_id                            = var.subnet_id # null = AWS picks a default subnet
  vpc_security_group_ids               = [aws_security_group.ws.id]
  iam_instance_profile                 = data.aws_iam_instance_profile.ws.name
  associate_public_ip_address          = true # outbound internet without paying for a NAT gateway
  instance_initiated_shutdown_behavior = "terminate"

  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 3          # LAB ONLY: lets pods in kind reach the instance role
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    gh_user               = var.gh_user
    git_branch            = var.git_branch
    ssh_public_key        = trimspace(file(pathexpand(var.ssh_public_key_path)))
    auto_shutdown_minutes = var.auto_shutdown_minutes
    lab_profiles          = var.lab_profiles # fast-track kit: "" = lab.env decides
    lab_steps             = var.lab_steps
  })
  user_data_replace_on_change = true

  tags = {
    Name = "roboshop-lab"
  }
}
