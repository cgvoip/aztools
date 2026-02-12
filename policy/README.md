# Azure Policy: Enforce Windows VM `licenseType` at Management Group Scope (Terraform)

This Terraform package creates an **Azure Policy Definition**, assigns it at a **Management Group**, and (optionally) starts a **remediation** to bring existing resources into compliance.

It is designed for **AzureRM provider v4** and uses the **Modify** policy effect to set the Windows VM `licenseType` property reliably.

---

## What this deploys

### Resources
- **Policy Definition** (custom): Enforces `Microsoft.Compute/virtualMachines/licenseType`
- **Policy Assignment** at **Management Group** scope
- **Policy Remediation** *(optional)*: Triggers remediation for existing non-compliant resources

### Behavior
- For **Windows VMs**, if `licenseType` is missing or incorrect, policy will **modify** the resource to the desired value (e.g., `Windows_Server`).
- Remediation will apply the change to existing non-compliant VMs (if enabled).

---

## Prerequisites

- Terraform **>= 1.5** (recommended)
- AzureRM provider **~> 4.0**
- An Azure identity with permissions to:
  - Create policy definitions/assignments at the target **Management Group**
  - Create policy remediations (if enabled)
- **Management Group ID** (not display name), e.g.:
  - `/providers/Microsoft.Management/managementGroups/mg-platform`

---

## Files

- `provider.tf` – provider configuration
- `variables.tf` – input variables
- `terraform.tfvars` – environment-specific values
- `locals.tf` – locals and policy document definitions
- `main.tf` – policy definition, assignment, remediation
- `outputs.tf` – useful IDs/outputs

---

## Inputs

Key variables you will typically set in `terraform.tfvars`:

| Variable | Type | Description |
|---|---:|---|
| `management_group_id` | string | Management Group resource ID to assign policy to |
| `policy_assignment_name` | string | Name of the policy assignment |
| `policy_assignment_location` | string | Location required for managed identity on MG assignment |
| `license_type` | string | Desired Windows `licenseType` value (e.g. `Windows_Server`) |
| `policy_effect` | string | Policy effect (`Modify`, `Audit`, `Disabled`) |
| `create_remediations` | bool | Whether to create a remediation task |
| `remediation_parallel_deployments` | number | (Optional) Parallelism for remediation |
| `remediation_failure_threshold` | number | (Optional) Failure threshold for remediation |

> **Note:** `policy_assignment_location` is required when the assignment uses a Managed Identity (needed for **Modify**).

---

## Usage

### 1) Authenticate
Use any of these approaches:
- `az login` (interactive)
- Managed Identity in CI
- Service Principal via environment variables

Example (Azure CLI login):
```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
```

### 2) Initialize and apply
```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

---

## Example `terraform.tfvars`

```hcl
management_group_id          = "/providers/Microsoft.Management/managementGroups/mg-platform"
policy_assignment_name       = "enforce-windows-license-type"
policy_assignment_location   = "westeurope"

# What to enforce
license_type   = "Windows_Server"
policy_effect  = "Modify"

# Remediation
create_remediations               = true
remediation_parallel_deployments  = 10
remediation_failure_threshold     = 0.1
```

---

## Outputs

After apply, Terraform will output IDs you can use for automation/debugging, including:
- Policy definition ID
- Policy assignment ID
- Remediation ID (if created)

---

## Operational Notes

### Modify effect requires permissions
- The policy assignment uses a **Managed Identity**.
- Azure will grant required permissions using the `roleDefinitionIds` declared in the policy rule.
- If remediation or modification doesn’t occur, check:
  - Assignment identity exists and is enabled
  - The identity has adequate roles at scope
  - Policy compliance scan has run (can take time)

### Remediation timing
- Remediation tasks work against the latest compliance state.
- If you just deployed the assignment, you may need to wait for compliance evaluation or trigger a scan.

---

## Troubleshooting

### Policy assignment deploys but nothing changes
- Ensure:
  - `policy_effect = "Modify"`
  - Assignment has a managed identity
  - Identity has permissions at the MG scope
- Check compliance:
  - Azure Portal → Policy → Compliance

### Remediation creation fails
- Confirm the AzureRM provider version is v4+ compatible and that your identity can create remediations at MG scope.

---

## Formatting & Quality

Before committing changes:
```bash
terraform fmt -recursive
terraform validate
```

---

## License / Disclaimer

This code is provided as-is. Always test in a sandbox before rolling out broadly.
