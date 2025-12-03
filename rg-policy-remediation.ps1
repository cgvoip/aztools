<#
.SYNOPSIS
    Azure Policy Remediation Runbook – RG Scoped ONLY
    - ONLY remediates INDIVIDUAL (non-initiative) policy assignments
    - Ignores all policies that are part of an initiative
    - Only triggers for assignments directly scoped to the Resource Group
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

Write-Output "Starting RG-Scoped NON-INITIATIVE Policy Remediation Runbook - $(Get-Date)"

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
        $rgName  = $rg.ResourceGroupName
        $rgScope = $rg.ResourceId

        Write-Output "-- Checking RG: $rgName"

        # Get only NonCompliant policy states in this RG
        $complianceResults = Get-AzPolicyState `
            -ResourceGroupName $rgName `
            -ErrorAction SilentlyContinue | 
            Where-Object { $_.ComplianceState -eq "NonCompliant" }

        if (-not $complianceResults) {
            Write-Output "-- No non-compliant policies found."
            continue
        }

        # FILTER 1: Only assignments directly scoped to this RG
        $complianceResults = $complianceResults | Where-Object { $_.PolicyAssignmentScope -eq $rgScope }

        if (-not $complianceResults) {
            Write-Output "-- No RG-scoped assignments found."
            continue
        }

        # FILTER 2: EXCLUDE any policy that is part of an initiative
        # PolicyDefinitionReferenceId is ONLY populated when the policy comes from an initiative
        $complianceResults = $complianceResults | Where-Object { 
            [string]::IsNullOrWhiteSpace($_.PolicyDefinitionReferenceId) 
        }

        if (-not $complianceResults) {
            Write-Output "-- No non-compliant INDIVIDUAL (non-initiative) policies found."
            continue
        }

        # Optional: Filter by specific target assignment names/IDs
        if ($TargetPolicyAssignmentNamesOrIds.Count -gt 0) {
            $complianceResults = $complianceResults | Where-Object {
                $id   = $_.PolicyAssignmentId
                $name = $_.PolicyAssignmentName
                ($id -in $TargetPolicyAssignmentNamesOrIds) -or
                ($name -in $TargetPolicyAssignmentNamesOrIds)
            }

            if (-not $complianceResults) {
                Write-Output "-- No matching target assignments found."
                continue
            }
        }

        # Group by assignment (should be one per standalone policy)
        $assignmentsToRemediate = $complianceResults |
            Group-Object PolicyAssignmentId |
            ForEach-Object {
                [pscustomobject]@{
                    PolicyAssignmentId   = $_.Name
                    PolicyAssignmentName = $_.Group[0].PolicyAssignmentName
                    PolicyDefinitionId   = $_.Group[0].PolicyDefinitionId
                }
            }

        Write-Output "Found $($assignmentsToRemediate.Count) non-compliant INDIVIDUAL policy assignment(s) to remediate."

        # Check for in-progress remediations to avoid conflicts
        $pendingRemediations = @()
        try {
            $pendingRemediations = Get-AzPolicyRemediation `
                -ResourceGroupName $rgName `
                -Top 1000 `
                -Filter "ProvisioningState eq 'Running' or ProvisioningState eq 'Accepted' or ProvisioningState eq 'Submitted'" `
                -ErrorAction Stop
        }
        catch {
            # Fallback if filter not supported in older API versions
            $allRem = Get-AzPolicyRemediation -ResourceGroupName $rgName -Top 500 -ErrorAction SilentlyContinue
            $pendingRemediations = $allRem | Where-Object { $_.ProvisioningState -notin 'Succeeded','Failed','Canceled' }
        }

        foreach ($assign in $assignmentsToRemediate) {
            $assignmentId   = $assign.PolicyAssignmentId
            $assignmentName = $assign.PolicyAssignmentName

            if ($pendingRemediations | Where-Object PolicyAssignmentId -EQ $assignmentId) {
                Write-Output "-- Remediation already running for: $assignmentName – skipping"
                continue
            }

            try {
                Write-Output "-- Starting remediation for INDIVIDUAL policy: $assignmentName"
                $remediation = Start-AzPolicyRemediation `
                    -ResourceGroupName $rgName `
                    -PolicyAssignmentId $assignmentId `
                    -ErrorAction Stop

                Write-Output "-- Remediation job created: $($remediation.Name)"
                $counter++
            }
            catch {
                Write-Warning "-- Failed to start remediation for $assignmentName : $_"
            }
        }

        # Memory cleanup every 10 RGs
        if ($counter % 10 -eq 0) { [GC]::Collect() }
    }
}

Write-Output "`nRG-Scoped NON-INITIATIVE Policy Remediation Runbook completed - $(Get-Date)"
Write-Output "Total individual policy remediations started: $counter"