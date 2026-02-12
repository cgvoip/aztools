management_group_ids = [
  "/providers/Microsoft.Management/managementGroups/mg-platform",
  "/providers/Microsoft.Management/managementGroups/mg-landingzones",
  "/providers/Microsoft.Management/managementGroups/mg-sandbox"
]

policy_effect = "Modify"

# Required for MG policy assignments with managed identity
policy_assignment_location = "westeurope"

# Remediation tasks
create_remediations              = true
remediation_parallel_deployments = 10
remediation_failure_percentage   = 100