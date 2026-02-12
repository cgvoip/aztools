output "policy_definition_id" {
  value       = azurerm_policy_definition.custom.id
  description = "ID of the created custom policy definition."
}

output "policy_assignment_ids" {
  value       = { for k, v in azurerm_management_group_policy_assignment.assignment : k => v.id }
  description = "Map of management group IDs to policy assignment IDs."
}

output "policy_remediation_ids" {
  value       = { for k, v in azurerm_management_group_policy_remediation.remediation : k => v.id }
  description = "Map of management group IDs to remediation IDs (empty if create_remediations=false)."
}
