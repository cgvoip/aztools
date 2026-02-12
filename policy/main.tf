# ────────────────────────────────────────────────────────────────────────────────
# Custom Policy Definition
# ────────────────────────────────────────────────────────────────────────────────
resource "azurerm_policy_definition" "hybrid_benefit_windows" {
  name                  = local.policy_name
  policy_type           = "Custom"
  mode                  = "Indexed"
  display_name          = local.policy_display_name
  description           = local.policy_description
  management_group_name = replace(element(split("/", element(var.management_group_ids, 0)), length(split("/", element(var.management_group_ids, 0))) - 1), "mg-", "") # Use first MG name as scope for definition (change if needed)

  metadata = <<METADATA
{
  "category": "${local.policy_category}",
  "version": "1.0.0"
}
METADATA

  policy_rule = <<POLICY_RULE
{
  "if": {
    "allOf": [
      {
        "field": "type",
        "equals": "Microsoft.Compute/virtualMachines"
      },
      {
        "field": "Microsoft.Compute/imagePublisher",
        "in": ["MicrosoftWindowsServer", "MicrosoftWindowsDesktop", "microsoftwindowsdesktop"]
      },
      {
        "field": "Microsoft.Compute/imageOffer",
        "in": ["WindowsServer", "windows-10", "windows-11", "windows-365", "windows365"]
      },
      {
        "not": {
          "field": "Microsoft.Compute/virtualMachines/licenseType",
          "equals": "Windows_Server"
        }
      }
    ]
  },
  "then": {
    "effect": "[parameters('effect')]",
    "details": {
      "type": "Microsoft.Compute/virtualMachines",
      "existenceCondition": {
        "field": "Microsoft.Compute/virtualMachines/licenseType",
        "equals": "Windows_Server"
      },
      "deployment": {
        "properties": {
          "mode": "incremental",
          "template": {
            "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "vmName": {
                "type": "string"
              },
              "location": {
                "type": "string"
              }
            },
            "variables": {},
            "resources": [
              {
                "type": "Microsoft.Compute/virtualMachines",
                "apiVersion": "2024-07-01",
                "name": "[parameters('vmName')]",
                "location": "[parameters('location')]",
                "properties": {
                  "licenseType": "Windows_Server"
                }
              }
            ],
            "outputs": {}
          },
          "parameters": {
            "vmName": {
              "value": "[field('name')]"
            },
            "location": {
              "value": "[field('location')]"
            }
          }
        }
      }
    }
  }
}
POLICY_RULE

  parameters = <<PARAMETERS
{
  "effect": {
    "type": "String",
    "metadata": {
      "displayName": "Effect",
      "description": "DeployIfNotExists, AuditIfNotExists or Disabled the execution of the Policy"
    },
    "allowedValues": [
      "DeployIfNotExists",
      "AuditIfNotExists",
      "Disabled"
    ],
    "defaultValue": "DeployIfNotExists"
  }
}
PARAMETERS
}

# ────────────────────────────────────────────────────────────────────────────────
# Policy Assignments + Remediations (one per management group)
# ────────────────────────────────────────────────────────────────────────────────
resource "azurerm_management_group_policy_assignment" "hybrid_benefit" {
  for_each             = toset(var.management_group_ids)
  name                 = "${local.policy_name}-assignment"
  display_name         = "${local.policy_display_name} Assignment"
  description          = "Enforces Azure Hybrid Benefit for eligible Windows VMs"
  policy_definition_id = azurerm_policy_definition.hybrid_benefit_windows.id
  management_group_id  = each.value

  parameters = <<PARAMETERS
{
  "effect": {
    "value": "${var.policy_effect}"
  }
}
PARAMETERS

  location = "westeurope"  # required even if not used; pick any valid location
}

resource "azurerm_management_group_policy_remediation" "hybrid_benefit_remediation" {
  for_each                 = azurerm_management_group_policy_assignment.hybrid_benefit
  name                     = "${local.policy_name}-remediation-${replace(each.value.management_group_id, "/providers/Microsoft.Management/managementGroups/", "")}"
  management_group_id      = each.value.management_group_id
  policy_assignment_id     = each.value.id
  location_filters         = []   # empty = all locations
  failure_percentage       = 100  # adjust if you want partial failure tolerance
  parallel_deployments     = 10   # adjust concurrency
  resource_discovery_mode  = "ReEvaluateCompliance"
}