variable "management_group_ids" {
  description = "List of Azure Management Group IDs to assign the policy to (e.g. /providers/Microsoft.Management/managementGroups/your-mg-name)"
  type        = list(string)
  default     = []
}

variable "policy_effect" {
  description = "Effect to use for the policy assignment (must match one of the allowed values in the definition)"
  type        = string
  default     = "DeployIfNotExists"
  validation {
    condition     = contains(["DeployIfNotExists", "AuditIfNotExists", "Disabled"], var.policy_effect)
    error_message = "Effect must be one of: DeployIfNotExists, AuditIfNotExists, Disabled."
  }
}