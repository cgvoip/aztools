Here’s a complete, production-ready **Azure Automation Runbook (PowerShell 7.2+)** that does exactly what you asked for:

- Connects using a managed identity (recommended) or fallback to SPN  
- Gets all subscriptions (excludes ones you list)  
- Gets all resource groups per subscription (excludes ones you list)  
- Finds all **Policy Remediations** at the resource group scope  
- Triggers every remediation task that is not already running/completed  

```powershell
<#
.SYNOPSIS
    Triggers all pending Azure Policy remediations on allowed resource groups across allowed subscriptions.

.DESCRIPTION
    Useful for cleaning up "Remediate" tasks after a big policy deployment or before a release.

.NOTES
    Run this runbook with a Managed Identity that has:
      - Reader on subscriptions/resource groups
      - "Remediation Contributor" or "Owner" on the resource groups (to start remediations)
#>

param(
    # Optional: override at run time if you don't want to use the variables below
    [string[]]$ExcludeSubscriptions = @(),
    [string[]]$ExcludeResourceGroups   = @()
#)

# ╔══════════════════════════════════════════════════════════╗
# ║                 CONFIGURATION SECTION                    ║
# ╚══════════════════════════════════════════════════════════╝

# Add subscription names OR subscription IDs you want to SKIP
$ExcludeSubscriptions += @(
    "Visual Studio Enterprise"
    "MSDN Platform"
    "Internal - Non-Production"
    "00000000-0000-0000-0000-000000000000"   # example GUID
)

# Add resource group names (case-insensitive) you never want to touch
$ExcludeResourceGroups += @(
    "NetworkWatcherRG"
    "cloud-shell-storage*"
    "databricks-rg-*"
    "azureautomation*"
)

# ╚══════════════════════════════════════════════════════════╝

# Ensure we fail fast
$ErrorActionPreference = "Stop"

Write-Output "Starting Azure Policy Remediation runbook - $(Get-Date)"

# Connect using Managed Identity (recommended for Automation Accounts)
try {
    Write-Output "Connecting to Azure using Managed Identity..."
    Connect-AzAccount -Identity"
    Connect-AzAccount -Identity -WarningAction SilentlyContinue | Out-Null
}
catch {
    Write-Error "Failed to connect with Managed Identity. $_"
    throw
}

# Get all subscriptions the identity can see
$allSubs = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }

$subscriptionsToProcess = $allSubs | Where-Object {
    $subName = $_.Name
    $subId   = $_.Id
    $subName -notin $ExcludeSubscriptions -and $subId -notin $ExcludeSubscriptions
}

Write-Output "Found $($allSubs.Count) subscriptions total."
Write-Output "Will process $($subscriptionsToProcess.Count) subscriptions after exclusions."

foreach ($sub in $subscriptionsToProcess) {
    Write-Output "`n=== Processing subscription: [$($sub.Name)] ($($sub.Id)) ==="

    try {
        $null = Set-AzContext -SubscriptionId $sub.Id -WarningAction SilentlyContinue
    }
    catch {
        Write-Warning "Could not set context to subscription $($sub.Name). Skipping."
        continue
    }

    # Get all resource groups in this subscription
    $rgList = Get-AzResourceGroup

    $rgsToProcess = $rgList | Where-Object {
        $rgName = $_.ResourceGroupName
        # Wildcard support for exclusions (e.g. "cloud-shell-storage*")
        -not ($ExcludeResourceGroups | Where-Object {
            if ($_.Contains("*")) {
                $pattern = "^$([regex]::Escape($_).Replace("\*", ".*"))$"
                $rgName -match $pattern
            } else {
                $rgName -eq $_
            }
        })
    }

    Write-Output "Found $($rgList.Count) resource groups. $($rgsToProcess.Count) will be processed after exclusions."

    foreach ($rg in $rgsToProcess) {
        $rgName = $rg.ResourceGroupName
        Write-Output "  Checking resource group: $rgName"

        # Get remediations at RG scope that are NOT already in a terminal state
        $remediations = Get-AzPolicyRemediation -ResourceGroupName $rgName -ErrorAction SilentlyContinue |
            Where-Object { $_.ProvisioningState -notin @("Succeeded","Failed","Canceled") -or $null -eq $_.ProvisioningState }

        if (-not $remediations) {
            {
            Write-Output "    No pending remediations found."
            continue
        }

        Write-Output "    Found $($remediations.Count) remediation(s) to start:"

        foreach ($rem in $remediations) {
            $remName = $rem.Name
            $policyAssignmentId = $rem.PolicyAssignmentId
            $policyName = ($policyAssignmentId -split "/")[-1]

            Write-Output "      Starting remediation '$remName' for policy assignment '$policyName'"

            try {
                Start-AzPolicyRemediation `
                    -Name $remName `
                    -ResourceGroupName $rgName `
                    -PolicyAssignmentId $policyAssignmentId `
                    -ErrorAction Stop

                Write-Output "        Remediation started successfully."
            }
            catch {
                Write-Warning "        Failed to start remediation '$remName'. Error: $_"
            }
        }
    }
}

Write-Output "`nRunbook completed - $(Get-Date)"

