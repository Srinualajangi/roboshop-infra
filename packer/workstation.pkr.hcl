# roboshop-infra/packer/workstation.pkr.hcl
packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "kind_node_image" {
  type        = string
  default     = ""     # e.g. kindest/node:v1.3x.y@sha256:...  (from the kind release notes / versions.env)
  description = "kind node image to pre-pull so cluster creation does not download ~1 GB every day"
}

locals {
  ts = formatdate("YYYYMMDD-hhmm", timestamp())
}

source "amazon-ebs" "workstation" {
  region        = var.region
  instance_type = "m6i.large"           # build box only; ~15 min ≈ a few cents
  ssh_username  = "ec2-user"
  ami_name      = "roboshop-workstation-${local.ts}"
  ami_description = "RoboShop lab workstation: RHEL 9 + docker + kind/kubectl/helm/... (built by Packer)"

  source_ami_filter {
    filters = {
      name                = "RHEL-9.*_HVM-*-x86_64-*-Hourly2-GP3"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["309956199498"]       # Red Hat's official AWS account
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  deprecate_at = timeadd(timestamp(), "720h")   # marks the AMI deprecated after 30 days (still usable)

  tags = {
    Name      = "roboshop-workstation-${local.ts}"
    Project   = "roboshop"
    ManagedBy = "packer"
    BaseAMI   = "{{ .SourceAMI }}"
  }
}

build {
  sources = ["source.amazon-ebs.workstation"]

  # Ship the workstation folder (tools.sh + versions.env) from your repo into the build box
  provisioner "file" {
    source      = "../workstation"
    destination = "/tmp/workstation"
  }

  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "sudo dnf -y -q update",
      # SSM agent: RHEL does not include it (user_data installs it too, this just saves time)
      "sudo dnf install -y -q https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm",
      "sudo systemctl enable amazon-ssm-agent",
      # Run the SAME tools step the daily bootstrap runs — one source of truth
      "mkdir -p /tmp/infra && mv /tmp/workstation /tmp/infra/workstation",
      "INFRA_DIR=/tmp/infra bash /tmp/infra/workstation/steps/tools.sh",
      # Pre-pull big images into Docker's store (baked into the AMI)
      "if [ -n '${var.kind_node_image}' ]; then sudo docker pull '${var.kind_node_image}'; fi",
      "sudo docker pull busybox:1.36",
      # Clean up so every instance starts fresh
      "sudo rm -rf /tmp/infra /home/ec2-user/.ssh/authorized_keys",
      "sudo cloud-init clean --logs",
    ]
  }
}
