# roboshop-infra/terraform/40-eks/variables.tf
variable "kubernetes_version" {
  description = "Control plane version. Day 98: second-newest in standard support. Day 106: bump by ONE minor."
  type        = string
  default     = "1.36" # example — set what you found in Step 1
}

variable "node_kubernetes_version" {
  description = "Node group version. null = follow the control plane. Day 106 pins it to show the upgrade order."
  type        = string
  default     = null
}

variable "admin_cidrs" {
  description = "Who may reach the PUBLIC API endpoint. The Makefile passes your current IP /32."
  type        = list(string)
  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "Refusing to expose the EKS API to the whole internet. Pass your IP /32."
  }
}

variable "node_instance_types" {
  description = "Several similar types = more Spot pools = fewer capacity errors"
  type        = list(string)
  default     = ["m6i.large", "m5.large", "m6a.large", "t3.large"]
}

variable "workstation_access" {
  description = "Give the kind workstation role cluster-admin on EKS (used by the hub-and-spoke option on Day 103)"
  type        = bool
  default     = false
}

variable "enable_karpenter" {
  description = "Day 104"
  type        = bool
  default     = false
}

variable "enable_container_insights" {
  description = "Day 105: CloudWatch Observability add-on"
  type        = bool
  default     = false
}
