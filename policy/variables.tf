variable "management_group_ids" {
  description = "List of Azure Management Group IDs to assign the policy to (e.g. /providers/Microsoft.Management/managementGroups/your-mg-name)"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.management_group_ids) > 0
    error_message = "Provide at least one management group ID in management_group_ids."
  }
}

variable "policy_effect" {
  description = "Effect to use for the policy assignment (must match one of the allowed values in the definition). This module uses Modify by default."
  type        = string
  default     = "Modify"
  validation {
    condition     = contains(["Modify", "Audit", "Disabled"], var.policy_effect)
    error_message = "Effect must be one of: Modify, Audit, Disabled."
  }
}

variable "policy_assignment_location" {
  description = "Location used for the policy assignment (required by Azure when a managed identity is attached)."
  type        = string
  default     = "westeurope"
}

variable "create_remediations" {
  description = "Whether to create remediation tasks (one per management group assignment)."
  type        = bool
  default     = true
}

variable "remediation_parallel_deployments" {
  description = "Max number of concurrent deployments in a remediation task (Azure Policy)."
  type        = number
  default     = 10
  validation {
    condition     = var.remediation_parallel_deployments >= 1 && var.remediation_parallel_deployments <= 50
    error_message = "remediation_parallel_deployments must be between 1 and 50."
  }
}

variable "remediation_failure_percentage" {
  description = "Failure threshold percentage (0-100) for remediation tasks."
  type        = number
  default     = 100
  validation {
    condition     = var.remediation_failure_percentage >= 0 && var.remediation_failure_percentage <= 100
    error_message = "remediation_failure_percentage must be between 0 and 100."
  }
}