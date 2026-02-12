<#
.SYNOPSIS
    Remediates ALL non-compliant policies in a subscription
    except the policies/assignments you explicitly want to skip

.PARAMETER SubscriptionId
    Azure Subscription ID to work in

.PARAMETER SkipPolicyDefinitionIds
    List of Policy DEFINITION IDs you want to SKIP remediation for

.PARAMETER SkipPolicyAssignmentIds
    List of Policy ASSIGNMENT IDs you want to SKIP (more precise)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,

    [string[]] $SkipPolicyDefinitionIds = @(),

    [string[]] $SkipPolicyAssignmentIds = @(),

    [switch] $WhatIf
)

# ────────────────────────────────────────────────────────────────────────────────
#  Connect & Set context
# ────────────────────────────────────────────────────────────────────────────────
Connect-AzAccount -Identity -ErrorAction Stop    # ← use this in Automation / Managed Identity
# Connect-AzAccount                               # ← for testing from your computer

Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop

Write-Host "`nWorking in subscription: " -NoNewline
Write-Host (Get-AzContext).Subscription.Name -ForegroundColor Cyan

# ────────────────────────────────────────────────────────────────────────────────
#  Get all non-compliant policies
# ────────────────────────────────────────────────────────────────────────────────
Write-Host "`nGetting all NonCompliant policy states..." -ForegroundColor DarkCyan

$nonCompliant = Get-AzPolicyState -Filter "ComplianceState eq 'NonCompliant'" `
    -All `
    -ErrorAction Stop

Write-Host "Found" $nonCompliant.Count "non-compliant resources"

# ────────────────────────────────────────────────────────────────────────────────
#  Filter – keep only the ones we WANT to remediate
# ────────────────────────────────────────────────────────────────────────────────
$toRemediate = $nonCompliant | Where-Object {
    $currentPolicyDefId = $_.PolicyDefinitionId
    $currentAssignmentId = $_.PolicyAssignmentId

    # Skip if definition is in skip list
    if ($SkipPolicyDefinitionIds -contains $currentPolicyDefId) {
        return $false
    }

    # Skip if assignment is in skip list
    if ($SkipPolicyAssignmentIds -contains $currentAssignmentId) {
        return $false
    }

    # otherwise → remediate
    return $true
}

Write-Host "`nAfter filtering we will remediate" $toRemediate.Count "items" -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────────────────
#  Group by Assignment → better performance + cleaner
# ────────────────────────────────────────────────────────────────────────────────
$grouped = $toRemediate | Group-Object -Property PolicyAssignmentId

foreach ($group in $grouped) {
    $assignmentId = $group.Name
    $count = $group.Count

    Write-Host "Starting remediation on assignment: " -NoNewline
    Write-Host $assignmentId -ForegroundColor Yellow
    Write-Host "   → $count resource(s)"

    if ($WhatIf) {
        Write-Host "   (WhatIf - skipping actual remediation)" -ForegroundColor DarkMagenta
        continue
    }

    try {
        Start-AzPolicyRemediation `
            -Name "AutoRem-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
            -PolicyAssignmentId $assignmentId `
            -Location (Get-AzLocation).Location[0] `
            -ErrorAction Stop

        Write-Host "   → Remediation started" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed on assignment: $assignmentId"
        Write-Warning $_.Exception.Message
    }
}

Write-Host "`nFinished." -ForegroundColor Cyan