# roboshop-infra/terraform/modules/vpc/variables.tf
variable "name" {
  description = "Name prefix for every resource"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR. Must be a /16 because subnets are carved with cidrsubnet()"
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr, 0)) && endswith(var.cidr, "/16")
    error_message = "cidr must be a valid /16, e.g. 10.40.0.0/16."
  }
}

variable "azs" {
  description = "Exactly two AZs, e.g. [\"us-east-1a\", \"us-east-1b\"]"
  type        = list(string)
  validation {
    condition     = length(var.azs) == 2
    error_message = "This module is written for exactly 2 AZs."
  }
}

variable "enable_nat_gateway" {
  description = "Private app subnets get internet egress through NAT"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "true = one NAT in AZ a (cheap, AZ a is a single point of failure). false = one NAT per AZ (prod)"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "If set, adds EKS/Karpenter discovery tags for this cluster"
  type        = string
  default     = ""
}

variable "data_ports" {
  description = "TCP ports the data tier accepts from the app tier"
  type        = list(number)
  default     = [3306, 5432]
}

variable "enable_flow_logs" {
  description = "VPC flow logs to CloudWatch (1-day retention). Useful on Day 97 only."
  type        = bool
  default     = false
}
