# Example values

management_group_ids = [
  "/providers/Microsoft.Management/managementGroups/mg-platform"
]

policy_assignment_name     = "deploy-azure-hybrid-benefit-windows"
policy_assignment_location = "westeurope"

# Policy effect comes from the policy file's parameter set (if present)
policy_effect = "DeployIfNotExists"

# Optional extra parameters, if your policy definition declares them
policy_parameters = {}
