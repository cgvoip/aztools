output "policy_definition_id" {
  description = "The resource ID of the custom policy definition."
  value       = azurerm_policy_definition.hybrid_benefit_windows.id
}

output "policy_assignment_ids" {
  description = "Policy assignment IDs keyed by management group ID."
  value       = { for mg_id, a in azurerm_management_group_policy_assignment.hybrid_benefit : mg_id => a.id }
}

output "policy_assignment_identity_principal_ids" {
  description = "Managed identity principal IDs keyed by management group ID."
  value       = { for mg_id, a in azurerm_management_group_policy_assignment.hybrid_benefit : mg_id => a.identity[0].principal_id }
}
