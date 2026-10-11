# terraform/20-workstation/variables.tf
variable "owner" {
  type = string
}

variable "gh_user" {
  type        = string
  description = "Your GitHub username (repos are cloned from github.com/<gh_user>/...)"
}

variable "git_branch" {
  type    = string
  default = "main"
}

variable "ami_id" {
  type        = string
  description = "RHEL 9 based DevOps-tools AMI (us-east-1 only). Day 114 replaces it with your own Packer AMI."
  default     = "ami-0220d79f3f480ecf5"
}

variable "instance_type" {
  type        = string
  description = "8 vCPU / 32 GiB is plenty until Phase 7; then consider r6i.2xlarge (64 GiB). x86_64 only."
  default     = "m6i.2xlarge"
}

variable "use_spot" {
  type    = bool
  default = true
}

variable "subnet_id" {
  type        = string
  default     = null
  description = "Set a specific default-VPC subnet (AZ) if Spot capacity is short in the one AWS picks"
}

variable "root_volume_gb" {
  type    = number
  default = 80
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/roboshop_lab.pub"
}

variable "auto_shutdown_minutes" {
  type        = number
  default     = 180
  description = "Dead-man switch: the instance terminates itself after this many minutes"
  validation {
    condition     = var.auto_shutdown_minutes >= 30 && var.auto_shutdown_minutes <= 480
    error_message = "Pick between 30 and 480 minutes."
  }
}

# fast-track kit: one-boot overrides used by "make up-full" (empty = use workstation/lab.env from Git)
variable "lab_profiles" {
  type        = string
  default     = ""
  description = "Override LAB_PROFILES for this boot only, e.g. \"obs sec ci\". Empty = lab.env decides."
}

variable "lab_steps" {
  type        = string
  default     = ""
  description = "Override LAB_STEPS for this boot only. Empty = lab.env decides."
}
