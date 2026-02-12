# ────────────────────────────────────────────────────────────────────────────────
# Azure Policy: Enforce Azure Hybrid Benefit (Windows licenseType)
#
# Implementation choices:
# - Uses the "Modify" effect (more reliable than DeployIfNotExists for simple
#   property changes like licenseType).
# - Assignment uses a System Assigned Managed Identity.
# - Role required: Virtual Machine Contributor.
#
# If you truly need DeployIfNotExists (DINE), this can be reworked, but Modify
# generally creates fewer deployment/template edge-cases.
# ────────────────────────────────────────────────────────────────────────────────

# Role used by Azure Policy managed identity when effect = Modify.
# Built-in role ID is stable across clouds.
# Virtual Machine Contributor: 9980e02c-c2be-4d73-94e8-173b1dc7cf3c
# Source: Azure built-in roles documentation.
locals {
  vm_contributor_role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/9980e02c-c2be-4d73-94e8-173b1dc7cf3c"

  # Use the first management group as the scope that holds the policy definition.
  # (Policy assignments can still target multiple MGs.)
  definition_management_group_name = element(
    split("/", var.management_group_ids[0]),
    length(split("/", var.management_group_ids[0])) - 1
  )

  policy_parameters = {
    effect = {
      type = "String"
      metadata = {
        displayName = "Effect"
        description = "Modify, Audit, or Disabled the execution of the Policy"
      }
      allowedValues = [
        "Modify",
        "Audit",
        "Disabled",
      ]
      defaultValue = "Modify"
    }
  }

  policy_rule = {
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Compute/virtualMachines"
        },
        {
          field = "Microsoft.Compute/imagePublisher"
          in    = ["MicrosoftWindowsServer", "MicrosoftWindowsDesktop", "microsoftwindowsdesktop"]
        },
        {
          field = "Microsoft.Compute/imageOffer"
          in    = ["WindowsServer", "windows-10", "windows-11", "windows-365", "windows365"]
        },
        {
          not = {
            field  = "Microsoft.Compute/virtualMachines/licenseType"
            equals = "Windows_Server"
          }
        },
      ]
    }

    then = {
      effect = "[parameters('effect')]"

      # Details are used by the Modify effect.
      details = {
        roleDefinitionIds = [local.vm_contributor_role_definition_id]
        operations = [
          {
            operation = "addOrReplace"
            field     = "Microsoft.Compute/virtualMachines/licenseType"
            value     = "Windows_Server"
          }
        ]
      }
    }
  }
}

# ────────────────────────────────────────────────────────────────────────────────
# Custom Policy Definition
# ────────────────────────────────────────────────────────────────────────────────
resource "azurerm_policy_definition" "hybrid_benefit_windows" {
  name                  = local.policy_name
  policy_type           = "Custom"
  mode                  = "Indexed"
  display_name          = local.policy_display_name
  description           = local.policy_description
  management_group_name = local.definition_management_group_name

  metadata    = jsonencode({ category = local.policy_category, version = "1.1.0" })
  parameters  = jsonencode(local.policy_parameters)
  policy_rule = jsonencode(local.policy_rule)
}

# ────────────────────────────────────────────────────────────────────────────────
# Policy Assignments + (Optional) Remediations (one per management group)
# ────────────────────────────────────────────────────────────────────────────────
resource "azurerm_management_group_policy_assignment" "hybrid_benefit" {
  for_each             = toset(var.management_group_ids)

  # Name must be <= 24 chars for some assignment types; keep it short and stable.
  name                 = substr("${local.policy_name}-ab", 0, 24)
  display_name         = "${local.policy_display_name} (Assign)"
  description          = "Enforces Azure Hybrid Benefit by setting licenseType=Windows_Server on eligible Windows VMs"
  policy_definition_id = azurerm_policy_definition.hybrid_benefit_windows.id
  management_group_id  = each.value

  # Required for Modify / DeployIfNotExists.
  identity {
    type = "SystemAssigned"
  }

  # Still required by the AzureRM provider for MG policy assignments with identity.
  location = var.policy_assignment_location

  parameters = jsonencode({
    effect = {
      value = var.policy_effect
    }
  })

  lifecycle {
    precondition {
      condition     = length(var.management_group_ids) > 0
      error_message = "management_group_ids must contain at least one management group ID."
    }
  }
}

resource "azurerm_management_group_policy_remediation" "hybrid_benefit" {
  for_each = var.create_remediations ? azurerm_management_group_policy_assignment.hybrid_benefit : {}

  name                = substr("${local.policy_name}-remed-${replace(each.key, "/providers/Microsoft.Management/managementGroups/", "")}", 0, 64)
  management_group_id = each.value.management_group_id
  policy_assignment_id = each.value.id

  # Empty list = all locations.
  location_filters     = []

  # The following are optional tuning knobs.
  failure_percentage   = var.remediation_failure_percentage
  parallel_deployments = var.remediation_parallel_deployments
}
