<#
.SYNOPSIS
    Azure Policy Remediation Runbook for RG scoped Assignments only
    - Only triggers remediation for policy assignments that are directly scoped to the Resource Group
    - Looks at actual compliance state to avoid running remediation for compliant assignments
    - Remediates individual policies and each policy in initiatives one per assignment, even if multiple are non-compliant

#>

# 1. Add subscription name or ID to skip
$ExcludeSubscriptions = @()

# 2. Add resource groups and supports * wildcard
$ExcludeResourceGroups = @()

# 3. Specify assignment name OR full Assignment ID for policy or initiative
#     Leave empty @() to allow all assignments
$TargetPolicyAssignmentNamesOrIds = @()

$ErrorActionPreference = "Stop"
$counter = 0

Write-Output "Starting RG Scoped Smart Policy Remediation Runbook - $(Get-Date)"

# Connect with Managed Identity
try {
    Write-Output "Authenticating with managed identity"
    Connect-AzAccount -Identity | Out-Null
}
catch {
    Write-Error "Failed to connect with managed identity: $_"
    throw
}

# Get enabled subscriptions
$allSubs = Get-AzSubscription | Where-Object State -eq "Enabled"
$subsToProcess = $allSubs | Where-Object {
    $_.Name -notin $ExcludeSubscriptions -and $_.Id -notin $ExcludeSubscriptions
}

Write-Output "Processing $($subsToProcess.Count) subscriptions`n"

foreach ($sub in $subsToProcess) {
    Write-Output "=== Subscription: [$($sub.Name)] ($($sub.Id)) ==="
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    $rgs = Get-AzResourceGroup | Where-Object {
        $name = $_.ResourceGroupName
        -not ($ExcludeResourceGroups | Where-Object {
            if ($_.Contains('*')) { $name -like $_ } else { $name -eq $_ }
        })
    }

    Write-Output "Scanning $($rgs.Count) resource groups..."

    foreach ($rg in $rgs) {
        $rgName   = $rg.ResourceGroupName
        $rgScope  = $rg.ResourceId  

        Write-Output "  → Checking RG: $rgName"

        # Get only non-compliant states for this RG
        $complianceResults = Get-AzPolicyState `
            -ResourceGroupName $rgName `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.ComplianceState -eq "NonCompliant" }

        if (-not $complianceResults) {
            Write-Output "    Compliant – nothing to do"
            continue
        }

        # Filter to only assignments that are directly scoped to this RG
        $complianceResults = $complianceResults | Where-Object { $_.PolicyAssignmentScope -eq $rgScope }

        if (-not $complianceResults) {
            Write-Output "No non-compliant RG scoped assignments skipping"
            continue
        }

        # Identifies any specified target assignments
        if ($TargetPolicyAssignmentNamesOrIds.Count -gt 0) {
            $complianceResults = $complianceResults | Where-Object {
                $id   = $_.PolicyAssignmentId
                $name = $_.PolicyAssignmentName

                ($id -in $TargetPolicyAssignmentNamesOrIds) -or
                ($name -in $TargetPolicyAssignmentNamesOrIds)
            }

            if (-not $complianceResults) {
                Write-Output "No non-compliant target RG scoped assignments skipping"
                continue
            }
        }

        # Group by assignment ID to handle policies in initiatives correctly by using only one remediation per assignment
        $assignmentsToRemediate = $complianceResults |
            Group-Object PolicyAssignmentId |
            ForEach-Object {
                [pscustomobject]@{
                    PolicyAssignmentId   = $_.Name
                    PolicyAssignmentName = $_.Group[0].PolicyAssignmentName
                    NonCompliantComponents = $_.Count
                }
            }

        Write-Output "Found $($assignmentsToRemediate.Count) non-compliant RG scoped assignment(s) remediation check"

        # Get pending remediations to avoid conflicts and failures
        $pendingRemediations = @()
        try {
            $pendingRemediations = Get-AzPolicyRemediation `
                -ResourceGroupName $rgName `
                -Top 1000 `
                -Filter "ProvisioningState eq 'Accepted' or ProvisioningState eq 'Running' or ProvisioningState eq 'Submitted'" `
                -ErrorAction Stop
        }
        catch {
            $pendingRemediations = Get-AzPolicyRemediation -ResourceGroupName $rgName -Top 500 |
                Where-Object { $_.ProvisioningState -notin 'Succeeded','Failed','Canceled' }
        }

        foreach ($assign in $assignmentsToRemediate) {
            $assignmentId   = $assign.PolicyAssignmentId
            $assignmentName = $assign.PolicyAssignmentName

            if ($pendingRemediations | Where-Object PolicyAssignmentId -EQ $assignmentId) {
                Write-Output "      Remediation already in progress for: $assignmentName"
                continue
            }

            try {
                Write-Output "      Starting remediation for RG scoped assignment: $assignmentName $(if($assign.NonCompliantComponents -gt 1){"(initiative – $($assign.NonCompliantComponents) components non-compliant)"})"
                $newRem = Start-AzPolicyRemediation `
                    -ResourceGroupName $rgName `
                    -PolicyAssignmentId $assignmentId `
                    -ErrorAction Stop

                Write-Output "        Remediation created: $($newRem.Name)"
            }
            catch {
                Write-Warning "        Failed to start remediation for $assignmentName : $_"
            }
        }

        # Memory cleanup every 10 RGs
        if (++$counter % 10 -eq 0) { [GC]::Collect() }
    }
}

Write-Output "`nRG-Scoped Smart Remediation Runbook completed - $(Get-Date)"