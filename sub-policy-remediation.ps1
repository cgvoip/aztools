<#
.SYNOPSIS
    Azure Policy Remediation Runbook – SUBSCRIPTION Scoped ONLY
    → ONLY remediates INDIVIDUAL (non-initiative) policy assignments
    → Ignores all policies that are part of an initiative
    → Only triggers for assignments directly scoped to the Subscription
#>

# Subscriptions to completely skip (name or ID)
$ExcludeSubscriptions = @()

# Optionally limit to specific assignment names or full Assignment IDs
# Leave empty @() to allow all qualifying assignments
$TargetPolicyAssignmentNamesOrIds = @()

$ErrorActionPreference = "Stop"
$counter = 0

Write-Output "Starting SUBSCRIPTION-Scoped NON-INITIATIVE Policy Remediation Runbook - $(Get-Date)"

# Authenticate with Managed Identity
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
    
    $subScope = "/subscriptions/$($sub.Id)"
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    # Get only NonCompliant policy states at subscription scope
    $complianceResults = Get-AzPolicyState `
        -Scope $subScope `
        -ErrorAction SilentlyContinue | 
        Where-Object { $_.ComplianceState -eq "NonCompliant" }

    if (-not $complianceResults) {
        Write-Output "-- No non-compliant policies found at subscription scope."
        continue
    }

    # FILTER 1: Only assignments directly scoped to THIS subscription
    $complianceResults = $complianceResults | Where-Object { $_.PolicyAssignmentScope -eq $subScope }

    if (-not $complianceResults) {
        Write-Output "-- No subscription-scoped policy assignments found."
        continue
    }

    # FILTER 2: EXCLUDE any policy that belongs to an initiative
    $complianceResults = $complianceResults | Where-Object { 
        [string]::IsNullOrWhiteSpace($_.PolicyDefinitionReferenceId) 
    }

    if (-not $complianceResults) {
        Write-Output "-- No non-compliant INDIVIDUAL (non-initiative) subscription-scoped policies found."
        continue
    }

    # Optional: Filter by specific target assignment names/IDs
    if ($TargetPolicyAssignmentNamesOrIds.Count -gt 0) {
        $complianceResults = $complianceResults | Where-Object {
            $id   = $_.PolicyAssignmentId
            $name = $_.PolicyAssignmentName
            ($id -in $TargetPolicyAssignmentNamesOrIds) -or ($name -in $TargetPolicyAssignmentNamesOrIds)
        }

        if (-not $complianceResults) {
            Write-Output "-- No matching target assignments found."
            continue
        }
    }

    # Group by assignment ID (one remediation per assignment)
    $assignmentsToRemediate = $complianceResults |
        Group-Object PolicyAssignmentId |
        ForEach-Object {
            [pscustomobject]@{
                PolicyAssignmentId   = $_.Name
                PolicyAssignmentName = $_.Group[0].PolicyAssignmentName
            }
        }

    Write-Output "Found $($assignmentsToRemediate.Count) non-compliant subscription-scoped individual policy assignment(s) to remediate."

    # Check for existing running remediations at subscription scope
    $pendingRemediations = @()
    try {
        $pendingRemediations = Get-AzPolicyRemediation `
            -Scope $subScope `
            -Top 1000 `
            -Filter "ProvisioningState eq 'Running' or ProvisioningState eq 'Accepted' or ProvisioningState eq 'Submitted'" `
            -ErrorAction Stop
    }
    catch {
        $allRem = Get-AzPolicyRemediation -Scope $subScope -Top 500 -ErrorAction SilentlyContinue
        $pendingRemediations = $allRem | Where-Object { $_.ProvisioningState -notin 'Succeeded','Failed','Canceled' }
    }

    foreach ($assign in $assignmentsToRemediate) {
        $assignmentId   = $assign.PolicyAssignmentId
        $assignmentName = $assign.PolicyAssignmentName

        if ($pendingRemediations | Where-Object PolicyAssignmentId -EQ $assignmentId) {
            Write-Output "-- Remediation already in progress for: $assignmentName – skipping"
            continue
        }

        try {
            Write-Output "-- Starting remediation for subscription-scoped policy: $assignmentName"
            $remediation = Start-AzPolicyRemediation `
                -Scope $subScope `
                -PolicyAssignmentId $assignmentId `
                -ErrorAction Stop

            Write-Output "-- Remediation job created: $($remediation.Name)"
            $counter++
        }
        catch {
            Write-Warning "-- Failed to start remediation for $assignmentName: $_"
        }
    }

    # Memory cleanup
    if ($counter % 10 -eq 0) { [GC]::Collect() }
}

Write-Output "`nSUBSCRIPTION-Scoped NON-INITIATIVE Policy Remediation Runbook completed - $(Get-Date)"
Write-Output "Total subscription-level individual policy remediations started: $counter"