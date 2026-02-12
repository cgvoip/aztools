variable "management_group_ids" {
  description = "List of Azure Management Group resource IDs to assign the policy to (e.g. /providers/Microsoft.Management/managementGroups/your-mg-name). The first entry is also used as the scope for creating the custom policy definition."
  type        = list(string)

  validation {
    condition     = length(var.management_group_ids) > 0
    error_message = "Provide at least one management group resource ID in management_group_ids."
  }
}

variable "policy_definition_file" {
  description = "Path to the policy definition JSON file in this repo (full policy document containing displayName, description, parameters, and policyRule)."
  type        = string
  default     = "${path.module}/policies/deploy-azure-hybrid-benefit-for-windows/azurepolicy.json"
}

variable "policy_definition_name" {
  description = "Optional override for the Azure Policy Definition name (resource name). If null, a safe name is derived from the policy JSON displayName."
  type        = string
  default     = null
}

variable "policy_effect" {
  description = "Effect to use for the policy assignment (must be allowed by the policy definition parameter 'effect')."
  type        = string
  default     = "DeployIfNotExists"

  validation {
    condition     = contains(["DeployIfNotExists", "AuditIfNotExists", "Disabled"], var.policy_effect)
    error_message = "policy_effect must be one of: DeployIfNotExists, AuditIfNotExists, Disabled."
  }
}

variable "policy_assignment_name" {
  description = "Base name for the policy assignment. The final name includes a suffix per management group."
  type        = string
  default     = "deploy-azure-hybrid-benefit-windows"
}

variable "policy_assignment_location" {
  description = "Location for the policy assignment managed identity (required for management group scope assignments using DeployIfNotExists)."
  type        = string
  default     = "westeurope"
}

variable "policy_parameters" {
  description = "Extra parameters to pass into the policy assignment. This module will automatically set the 'effect' parameter (if present in the policy JSON) to policy_effect."
  type        = map(any)
  default     = {}
}

variable "create_remediations" {
  description = "Whether to create policy remediation resources for each management group assignment."
  type        = bool
  default     = true
}

variable "remediation_parallel_deployments" {
  description = "Maximum number of parallel deployments when remediating (if supported by the scope/effect)."
  type        = number
  default     = 10
}

variable "remediation_failure_threshold" {
  description = "Failure threshold (0.0-1.0) for remediations."
  type        = number
  default     = 0.1

  validation {
    condition     = var.remediation_failure_threshold >= 0 && var.remediation_failure_threshold <= 1
    error_message = "remediation_failure_threshold must be between 0 and 1."
  }
}
