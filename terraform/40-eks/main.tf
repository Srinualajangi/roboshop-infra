# roboshop-infra/terraform/40-eks/main.tf
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # the EKS module itself requires >= 6.59; init picks the newest 6.x
    }
  }
  backend "s3" {
    key          = "40-eks/terraform.tfstate"
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
      Layer       = "40-eks"
    }
  }
}

data "aws_caller_identity" "me" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "roboshop-tfstate-${data.aws_caller_identity.me.account_id}"
    key    = "30-network/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  name       = "roboshop-eks"
  account_id = data.aws_caller_identity.me.account_id
  net        = data.terraform_remote_state.network.outputs
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0" # pin the MAJOR; .terraform.lock.hcl + `terraform init` records the exact one

  name               = local.name
  kubernetes_version = var.kubernetes_version

  # API endpoint: private for nodes, public only for your IP
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs

  # Access entries instead of the aws-auth ConfigMap
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true # the SSO role running terraform becomes cluster admin
  access_entries = var.workstation_access ? {
    workstation = {
      principal_arn = "arn:aws:iam::${local.account_id}:role/roboshop-workstation"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  } : {}

  vpc_id                   = local.net.vpc_id
  subnet_ids               = local.net.private_app_subnet_ids # nodes + pods
  control_plane_subnet_ids = local.net.private_app_subnet_ids # where EKS puts its cross-account ENIs

  # Control-plane logs: who did what (audit) + API errors. 1 day retention = pennies.
  enabled_log_types                      = ["api", "audit"]
  cloudwatch_log_group_retention_in_days = 1

  # Envelope-encrypt Kubernetes Secrets with a customer-managed KMS key (module creates it)
  encryption_config               = { resources = ["secrets"] }
  kms_key_deletion_window_in_days = 7

  addons = {
    vpc-cni                = { before_compute = true } # must exist before nodes join, or nodes stay NotReady
    eks-pod-identity-agent = { before_compute = true }
    coredns                = {}
    kube-proxy             = {}
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
    amazon-cloudwatch-observability = var.enable_container_insights ? {
      pod_identity_association = [{
        role_arn        = aws_iam_role.cw_agent.arn
        service_account = "cloudwatch-agent"
      }]
    } : null
  }

  eks_managed_node_groups = {
    prod = {
      ami_type           = "AL2023_x86_64_STANDARD"
      capacity_type      = "SPOT"
      instance_types     = var.node_instance_types
      min_size           = 1
      max_size           = 4
      desired_size       = 2
      kubernetes_version = var.node_kubernetes_version # null = same as control plane

      # Same label your kind prod node had, so envs/prod values (nodeSelector pool=prod) work unchanged
      labels = { pool = "prod" }

      update_config = { max_unavailable = 1 } # upgrade one node at a time (Day 106)
      # metadata_options: module default = IMDSv2 required + hop limit 1 → pods CANNOT reach IMDS (Day 101)
    }
  }

  node_security_group_tags = { "karpenter.sh/discovery" = local.name }
}
