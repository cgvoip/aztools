```powershell
<#
.SYNOPSIS
    Azure Policy Remediation Runbook – MANAGEMENT GROUP Scoped ONLY
    - ONLY remediates INDIVIDUAL (non-initiative) policy assignments
    - Ignores all policies that are part of an initiative
    - Only triggers for assignments directly scoped to the Management Group
#>

# Management Groups to completely skip (name only)
$ExcludeManagementGroups = @()

# Optionally limit to specific assignment names or full Assignment IDs
# Leave empty @() to allow all qualifying assignments
$TargetPolicyAssignmentNamesOrIds = @()

$ErrorActionPreference = "Stop"
$counter = 0

Write-Output "Starting MANAGEMENT GROUP-Scoped NON-INITIATIVE Policy Remediation Runbook - $(Get-Date)"

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

# Get all management groups (including nested)
$allMgs = Get-AzManagementGroup

# Filter out excluded ones
$mgsToProcess = $allMgs | Where-Object {
    $_.Name -notin $ExcludeManagementGroups
}

Write-Output "Processing $($mgsToProcess.Count) management groups`n"

foreach ($mg in $mgsToProcess) {
    Write-Output "=== Management Group: [$($mg.DisplayName)] ($($mg.Name)) ==="

    $mgName = $mg.Name

    # Get only NonCompliant policy states at this management group
    $complianceResults = Get-AzPolicyState `
        -ManagementGroupName $mgName `
        -ErrorAction SilentlyContinue | 
        Where-Object { $_.ComplianceState -eq "NonCompliant" }

    if (-not $complianceResults) {
        Write-Output "-- No non-compliant policies found at this management group."
        continue
    }

    # FILTER 1: Only assignments directly scoped to THIS management group
    $mgScope = "/providers/Microsoft.Management/managementGroups/$mgName"
    $complianceResults = $complianceResults | Where-Object { $_.PolicyAssignmentScope -eq $mgScope }

    if (-not $complianceResults) {
        Write-Output "-- No management-group-scoped policy assignments found."
        continue
    }

    # FILTER 2: EXCLUDE any policy that belongs to an initiative
    $complianceResults = $complianceResults | Where-Object { 
        [string]::IsNullOrWhiteSpace($_.PolicyDefinitionReferenceId) 
    }

    if (-not $complianceResults) {
        Write-Output "-- No non-compliant INDIVIDUAL (non-initiative) management-group-scoped policies found."
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

    Write-Output "Found $($assignmentsToRemediate.Count) non-compliant management-group-scoped individual policy assignment(s) to remediate."

    # Check for existing running remediations at this management group
    $pendingRemediations = @()
    try {
        $pendingRemediations = Get-AzPolicyRemediation `
            -ManagementGroupName $mgName `
            -Top 1000 `
            -Filter "ProvisioningState eq 'Running' or ProvisioningState eq 'Accepted' or ProvisioningState eq 'Submitted'" `
            -ErrorAction Stop
    }
    catch {
        $allRem = Get-AzPolicyRemediation -ManagementGroupName $mgName -Top 500 -ErrorAction SilentlyContinue
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
            Write-Output "-- Starting remediation for management-group-scoped policy: $assignmentName"
            $remediation = Start-AzPolicyRemediation `
                -ManagementGroupName $mgName `
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

Write-Output "`nMANAGEMENT GROUP-Scoped NON-INITIATIVE Policy Remediation Runbook completed - $(Get-Date)"
Write-Output "Total management-group-level individual policy remediations started: $counter"
