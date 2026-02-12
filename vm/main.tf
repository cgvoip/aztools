# ────────────────────────────────────────────────────────────────────────────────
# Custom Policy Definition (loaded from repo file)
# ────────────────────────────────────────────────────────────────────────────────
resource "azurerm_policy_definition" "custom" {
  name                  = local.policy_definition_name
  policy_type           = "Custom"
  mode                  = local.policy_mode
  display_name          = local.policy_display_name
  description           = local.policy_description
  management_group_name = local.definition_mg_name

  metadata    = jsonencode(local.policy_metadata)
  parameters  = jsonencode(local.policy_parameters_schema)
  policy_rule = jsonencode(local.policy_rule_obj)
}

# ────────────────────────────────────────────────────────────────────────────────
# Policy Assignment(s) at Management Group scope (one per MG)
# ────────────────────────────────────────────────────────────────────────────────
resource "azurerm_management_group_policy_assignment" "assignment" {
  for_each = { for mg_id in var.management_group_ids : mg_id => mg_id }

  name                 = "${var.policy_assignment_name}-${replace(each.value, "/providers/Microsoft.Management/managementGroups/", "")}"
  display_name         = local.policy_display_name
  description          = local.policy_description
  management_group_id  = each.value
  policy_definition_id = azurerm_policy_definition.custom.id
  location             = var.policy_assignment_location

  # Required for DeployIfNotExists/Modify at MG scope
  identity {
    type = "SystemAssigned"
  }

  # Convert { k = v } into Azure Policy's expected { k = { value = v } }
  parameters = jsonencode({
    for k, v in local.assignment_parameters :
    k => { value = v }
  })
}

# ────────────────────────────────────────────────────────────────────────────────
# Remediation (optional, one per assignment)
# Note: AzureRM v4 does not support resource_discovery_mode at MG scope.
# ────────────────────────────────────────────────────────────────────────────────
resource "azurerm_management_group_policy_remediation" "remediation" {
  for_each = var.create_remediations ? azurerm_management_group_policy_assignment.assignment : {}

  name                 = "remediate-${each.value.name}"
  management_group_id  = each.value.management_group_id
  policy_assignment_id = each.value.id

  parallel_deployments = var.remediation_parallel_deployments
  failure_percentage   = var.remediation_failure_threshold
}
