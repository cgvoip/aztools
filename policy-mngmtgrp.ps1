```powershell
<#
.SYNOPSIS
    Azure Policy Remediation Runbook – Resource Scoped ONLY
    - ONLY remediates INDIVIDUAL (non-initiative) policy assignments
    - Ignores all policies that are part of an initiative
    - Only triggers for assignments directly scoped to individual resources
#>

# Add subscription name or ID to skip
$ExcludeSubscriptions = @()

# Add resource groups (supports * wildcard)
$ExcludeResourceGroups = @()

# Optionally limit to specific assignment names or full Assignment IDs
# Leave empty @() to allow all qualifying assignments
$TargetPolicyAssignmentNamesOrIds = @()

$ErrorActionPreference = "Stop"
$counter = 0

Write-Output "Starting Resource-Scoped NON-INITIATIVE Policy Remediation Runbook - $(Get-Date)"

# Connect using Managed Identity
try {
    Write-Output "Authenticating with managed identity..."
    Connect-AzAccount -Identity | Out-Null
    Write-Output "Authentication successful."
}
catch {
    Write-Error "Failed to authenticate with managed identity: $_"
    throw
}

# Get enabled subscriptions to process
$allSubs = Get-AzSubscription | Where-Object State -eq "Enabled"
$subsToProcess = $allSubs | Where-Object {
    $_.Name -notin $ExcludeSubscriptions -and $_.Id -notin $ExcludeSubscriptions
}

Write-Output "Processing $($subsToProcess.Count) subscriptions`n"

foreach ($sub in $subsToProcess) {
    Write-Output "=== Subscription: [$($sub.Name)] ($($sub.Id)) ==="
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    # Get resource groups with wildcard exclusion support
    $rgs = Get-AzResourceGroup | Where-Object {
        $name = $_.ResourceGroupName
        -not ($ExcludeResourceGroups | Where-Object {
            if ($_.Contains('*')) { $name -like $_ } else { $name -eq $_ }
        })
    }

    Write-Output "Scanning $($rgs.Count) resource groups..."

    foreach ($rg in $rgs) {
        $rgName = $rg.ResourceGroupName

        Write-Output "-- Checking RG: $rgName"

        # Get all resources in this RG
        $resources = Get-AzResource -ResourceGroupName $rgName -ErrorAction SilentlyContinue

        if (-not $resources) {
            Write-Output "-- No resources found in RG."
            continue
        }

        Write-Output "-- Found $($resources.Count) resources to check."

        foreach ($resource in $resources) {
            $resourceId = $resource.ResourceId
            $resourceName = $resource.Name

            Write-Output "---- Checking resource: $resourceName ($resourceId)"

            # Get policy assignments directly scoped to this resource
            $assignments = Get-AzPolicyAssignment -Scope $resourceId -ErrorAction SilentlyContinue

            if (-not $assignments) {
                Write-Output "---- No policy assignments at resource scope."
                continue
            }

            # FILTER: Only individual policies (not initiatives)
            # Initiatives have PolicyDefinitionId containing '/policySetDefinitions/'
            $individualAssignments = $assignments | Where-Object {
                $_.Properties.PolicyDefinitionId -match '/policyDefinitions/'
            }

            if (-not $individualAssignments) {
                Write-Output "---- No individual (non-initiative) assignments found."
                continue
            }

            # Optional: Filter by specific target assignment names/IDs
            if ($TargetPolicyAssignmentNamesOrIds.Count -gt 0) {
                $individualAssignments = $individualAssignments | Where-Object {
                    $id   = $_.PolicyAssignmentId
                    $name = $_.Name
                    ($id -in $TargetPolicyAssignmentNamesOrIds) -or
                    ($name -in $TargetPolicyAssignmentNamesOrIds)
                }

                if (-not $individualAssignments) {
                    Write-Output "---- No matching target assignments found."
                    continue
                }
            }

            # For each assignment, check if the resource is non-compliant for it
            $assignmentsToRemediate = @()
            foreach ($assign in $individualAssignments) {
                $assignmentId = $assign.PolicyAssignmentId
                $assignmentName = $assign.Name

                # Get policy state for this specific resource and assignment
                $complianceResults = Get-AzPolicyState `
                    -ResourceId $resourceId `
                    -PolicyAssignmentId $assignmentId `
                    -ErrorAction SilentlyContinue | 
                    Where-Object { $_.ComplianceState -eq "NonCompliant" }

                if ($complianceResults) {
                    $assignmentsToRemediate += [pscustomobject]@{
                        PolicyAssignmentId   = $assignmentId
                        PolicyAssignmentName = $assignmentName
                    }
                }
            }

            if (-not $assignmentsToRemediate) {
                Write-Output "---- No non-compliant individual policies found."
                continue
            }

            Write-Output "---- Found $($assignmentsToRemediate.Count) non-compliant individual policy assignment(s) to remediate."

            # Check for in-progress remediations at resource scope
            $pendingRemediations = @()
            try {
                $pendingRemediations = Get-AzPolicyRemediation `
                    -Scope $resourceId `
                    -Top 1000 `
                    -Filter "ProvisioningState eq 'Running' or ProvisioningState eq 'Accepted' or ProvisioningState eq 'Submitted'" `
                    -ErrorAction Stop
            }
            catch {
                # Fallback if filter not supported
                $allRem = Get-AzPolicyRemediation -Scope $resourceId -Top 500 -ErrorAction SilentlyContinue
                $pendingRemediations = $allRem | Where-Object { $_.ProvisioningState -notin 'Succeeded','Failed','Canceled' }
            }

            foreach ($assign in $assignmentsToRemediate) {
                $assignmentId   = $assign.PolicyAssignmentId
                $assignmentName = $assign.PolicyAssignmentName

                if ($pendingRemediations | Where-Object PolicyAssignmentId -EQ $assignmentId) {
                    Write-Output "---- Remediation already running for: $assignmentName – skipping"
                    continue
                }

                try {
                    Write-Output "---- Starting remediation for individual policy: $assignmentName on resource $resourceName"
                    $remediation = Start-AzPolicyRemediation `
                        -PolicyAssignmentId $assignmentId `
                        -ErrorAction Stop

                    Write-Output "---- Remediation job created: $($remediation.Name)"
                    $counter++
                }
                catch {
                    Write-Warning "---- Failed to start remediation for $assignmentName : $_"
                }
            }
        }

        # Memory cleanup every 10 RGs
        if ($counter % 10 -eq 0) { [GC]::Collect() }
    }
}

Write-Output "`nResource-Scoped NON-INITIATIVE Policy Remediation Runbook completed - $(Get-Date)"
Write-Output "Total individual policy remediations started: $counter"
```