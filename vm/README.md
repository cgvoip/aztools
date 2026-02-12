# Deploy Azure Hybrid Benefit for Windows (Custom Policy) — Terraform

This repo deploys a **custom Azure Policy** (from a JSON file in this repo), assigns it at **Management Group** scope, and (optionally) creates **policy remediations**.

The policy enforces Azure Hybrid Benefit by setting `Microsoft.Compute/virtualMachines/licenseType` for eligible Windows VMs:
- `MicrosoftWindowsDesktop` → `Windows_Client`
- `MicrosoftWindowsServer`  → `Windows_Server`

## What gets created

- **azurerm_policy_definition** (Custom) at the first management group in `management_group_ids`
- **azurerm_management_group_policy_assignment** at each management group in `management_group_ids`
- **azurerm_management_group_policy_remediation** *(optional)* for each assignment

## Policy file location

The policy definition is loaded from a repo file:

- `policies/deploy-azure-hybrid-benefit-for-windows/azurepolicy.json`

Terraform uses:
- `jsondecode(file(var.policy_definition_file))` to load the policy document
- `jsonencode(...)` when sending the rule/parameters/metadata to Azure

## Prerequisites

- Terraform **>= 1.5**
- AzureRM provider **~> 4.0**
- Azure identity with permissions at the Management Group scope to:
  - Create Policy Definitions
  - Create Policy Assignments
  - Create Policy Remediations (if enabled)

## Inputs

Common variables (see `variables.tf` for the full list):

| Variable | Type | Purpose |
|---|---:|---|
| `management_group_ids` | list(string) | MG resource IDs to assign the policy to |
| `policy_definition_file` | string | Path to policy JSON in the repo |
| `policy_assignment_name` | string | Base name for assignments |
| `policy_assignment_location` | string | Location required for assignment managed identity |
| `policy_effect` | string | Must be one of: `DeployIfNotExists`, `AuditIfNotExists`, `Disabled` |
| `create_remediations` | bool | Create remediation tasks per MG assignment |

### Effect values (IMPORTANT)

This policy only allows:
- `DeployIfNotExists`
- `AuditIfNotExists`
- `Disabled`

If you set anything else, Terraform validation will fail (by design), and Azure would reject it anyway.

## Example `terraform.tfvars`

```hcl
management_group_ids = [
  "/providers/Microsoft.Management/managementGroups/mg-platform"
]

policy_assignment_name     = "deploy-azure-hybrid-benefit-windows"
policy_assignment_location = "westeurope"

policy_effect = "DeployIfNotExists"

policy_parameters = {}
create_remediations = true
remediation_parallel_deployments = 10
remediation_failure_threshold = 0.1
```

## Run

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

## Notes / Troubleshooting

### “Nothing is changing”
- Confirm `policy_effect = "DeployIfNotExists"` (Audit won’t change anything).
- Policy uses a **SystemAssigned** identity on the assignment (required for DINE at MG scope).
- Compliance evaluation and remediation are not instant; it can take time for Azure Policy to evaluate resources.

### Remediation fails or doesn’t start
- Confirm you have permissions to create remediations at MG scope.
- Remediations operate on the latest compliance results; you may need to wait for a compliance scan.

## Outputs

See `outputs.tf` for:
- Policy definition ID
- Assignment IDs
- Remediation IDs (if created)
