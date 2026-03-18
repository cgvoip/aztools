<#
.SYNOPSIS
    Azure Automation runbook that starts remediation tasks only for initiative assignments
    that are directly assigned at the resource group scope.

.DESCRIPTION
    This runbook:
      1. Authenticates to Azure using the Automation Account managed identity.
      2. Enumerates enabled subscriptions.
      3. Enumerates resource groups in each subscription.
      4. Finds initiative assignments that are directly scoped to each resource group.
      5. Looks for non-compliant policy states for that exact initiative assignment.
      6. Maps each non-compliant policy definition back to the initiative member's
         policyDefinitionReferenceId.
      7. Starts remediation only for remediatable policy effects:
         - deployIfNotExists
         - modify
      8. Skips scopes and resource groups listed in the exclusion parameters.

    Important notes:
      - This script only targets initiative assignments directly assigned to the
        resource group. It intentionally skips inherited assignments.
      - This script only starts remediation tasks for policies that support remediation.
      - This script avoids creating duplicate remediation tasks when a matching active
        remediation already exists.

.PARAMETER WhatIfOnly
    When supplied, the runbook logs what it would do but does not start remediation.

.PARAMETER ExcludedSubscriptionIds
    Array of subscription IDs to exclude from remediation processing.

.PARAMETER ExcludedResourceGroups
    Array of resource group names to exclude from remediation processing.
    Matching is by resource group name only, regardless of subscription.

.PARAMETER ExcludedResourceGroupIds
    Array of full resource group resource IDs to exclude from remediation processing.
    Use this when the same resource group name exists in multiple subscriptions and
    you need precise exclusions.

.EXAMPLE
    .\run-initiative-remedy-resource-group.automation.commented.ps1 -WhatIfOnly

.EXAMPLE
    .\run-initiative-remedy-resource-group.automation.commented.ps1 `
        -ExcludedSubscriptionIds @('00000000-0000-0000-0000-000000000000') `
        -ExcludedResourceGroups @('rg-network-prod','rg-landingzone')
#>

param(
    [switch]$WhatIfOnly,

    # Subscriptions listed here are skipped entirely.
    [string[]]$ExcludedSubscriptionIds = @(),

    # Resource groups with these names are skipped in every subscription.
    [string[]]$ExcludedResourceGroups = @(),

    # Full resource group IDs listed here are skipped exactly.
    [string[]]$ExcludedResourceGroupIds = @()
)

$ErrorActionPreference = 'Stop'

# Normalize exclusion input once so comparisons are fast and case-insensitive.
$ExcludedSubscriptionIdsNormalized = @($ExcludedSubscriptionIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToLowerInvariant() })
$ExcludedResourceGroupsNormalized = @($ExcludedResourceGroups | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToLowerInvariant() })
$ExcludedResourceGroupIdsNormalized = @($ExcludedResourceGroupIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToLowerInvariant() })

function Write-Log {
    <#
    .SYNOPSIS
        Writes timestamped log messages for Azure Automation job output.

    .DESCRIPTION
        Standardizes log output so the runbook is easier to follow in job history.
        Levels are informational only; the script still uses exceptions for stop/fail logic.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Output "[$ts] [$Level] $Message"
}

function Ensure-Module {
    <#
    .SYNOPSIS
        Verifies that a required Az module exists in the Automation account and imports it.

    .DESCRIPTION
        Azure Automation runbooks do not automatically have every Az module/version loaded.
        This function finds the newest available version of a module, imports it, and fails
        early with a clear message if the module is missing.
    #>
    param([Parameter(Mandatory=$true)][string]$Name)

    $loaded = Get-Module -Name $Name -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $loaded) {
        throw "Required module '$Name' is not available in this Automation account. Import/update it under Shared Resources > Modules."
    }

    Import-Module $Name -ErrorAction Stop | Out-Null
    Write-Log "Loaded module $Name version $($loaded.Version)"
}

function Connect-AutomationAzure {
    <#
    .SYNOPSIS
        Authenticates to Azure using the Automation Account managed identity.

    .DESCRIPTION
        Disables context autosave for the current process to avoid inherited context issues,
        then signs in with the runbook's managed identity. The initial subscription from the
        returned context is set explicitly so subsequent Az cmdlets operate predictably.
    #>
    Disable-AzContextAutosave -Scope Process | Out-Null

    try {
        $ctx = (Connect-AzAccount -Identity).Context
        if (-not $ctx) {
            throw 'Connect-AzAccount -Identity returned no context.'
        }

        Set-AzContext -SubscriptionId $ctx.Subscription -DefaultProfile $ctx | Out-Null
        Write-Log "Authenticated with managed identity. Initial subscription: $($ctx.Subscription)"
    }
    catch {
        throw "Managed identity authentication failed. Ensure the Automation account identity is enabled and has required RBAC. $($_.Exception.Message)"
    }
}

function Get-RemediatableEffects {
    <#
    .SYNOPSIS
        Returns the Azure Policy effects that support remediation tasks.

    .DESCRIPTION
        Only these policy effects are eligible for Start-AzPolicyRemediation.
        Policies using audit, deny, append, etc. are intentionally skipped.
    #>
    @('deployIfNotExists','modify')
}

function Get-PolicyEffectFromDefinitionId {
    <#
    .SYNOPSIS
        Reads a policy definition and returns its effect.

    .DESCRIPTION
        Initiative member remediation only makes sense for remediatable policy effects.
        This function loads the policy definition and reads the effect from the policy rule.
        The effect can be represented in slightly different locations depending on how the
        definition was authored, so both common paths are checked.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$PolicyDefinitionId
    )

    try {
        $def = Get-AzPolicyDefinition -Id $PolicyDefinitionId -ErrorAction Stop
        if ($null -ne $def.Properties.PolicyRule.then.effect) {
            return [string]$def.Properties.PolicyRule.then.effect
        }

        if ($null -ne $def.Properties.PolicyRule.then.details.effect) {
            return [string]$def.Properties.PolicyRule.then.details.effect
        }

        return $null
    }
    catch {
        Write-Log "Unable to read policy definition effect for $PolicyDefinitionId. $($_.Exception.Message)" 'WARN'
        return $null
    }
}

function Get-ExistingActiveRemediation {
    <#
    .SYNOPSIS
        Checks whether a remediation task already exists for the same assignment/member pair.

    .DESCRIPTION
        Prevents duplicate remediation tasks from being created when one already exists for:
          - the same scope
          - the same policy assignment
          - the same initiative member (policyDefinitionReferenceId)

        Tasks in accepted, running, evaluating, or succeeded states are treated as already present.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Scope,
        [Parameter(Mandatory=$true)][string]$PolicyAssignmentId,
        [Parameter(Mandatory=$true)][string]$PolicyDefinitionReferenceId
    )

    try {
        $existing = Get-AzPolicyRemediation -Scope $Scope -ErrorAction SilentlyContinue
        if (-not $existing) { return $null }

        return $existing | Where-Object {
            $_.PolicyAssignmentId -eq $PolicyAssignmentId -and
            $_.PolicyDefinitionReferenceId -eq $PolicyDefinitionReferenceId -and
            $_.ProvisioningState -in @('Accepted','Running','Evaluating','Succeeded')
        } | Select-Object -First 1
    }
    catch {
        Write-Log "Could not enumerate remediation tasks at scope $Scope. $($_.Exception.Message)" 'WARN'
        return $null
    }
}

function Test-IsExcludedSubscription {
    <#
    .SYNOPSIS
        Returns $true when the current subscription is in the exclusion list.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$SubscriptionId
    )

    return $SubscriptionId.Trim().ToLowerInvariant() -in $ExcludedSubscriptionIdsNormalized
}

function Test-IsExcludedResourceGroup {
    <#
    .SYNOPSIS
        Returns $true when the current resource group matches either exclusion list.

    .DESCRIPTION
        A resource group can be excluded by name or by full resource ID.
        Use resource ID exclusions when you need exact targeting across subscriptions.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$ResourceGroupName,
        [Parameter(Mandatory=$true)][string]$ResourceGroupId
    )

    $rgNameNormalized = $ResourceGroupName.Trim().ToLowerInvariant()
    $rgIdNormalized = $ResourceGroupId.Trim().ToLowerInvariant()

    return (($rgNameNormalized -in $ExcludedResourceGroupsNormalized) -or ($rgIdNormalized -in $ExcludedResourceGroupIdsNormalized))
}

# Validate that the runbook has the modules it needs before doing anything else.
Ensure-Module -Name Az.Accounts
Ensure-Module -Name Az.Resources
Ensure-Module -Name Az.PolicyInsights

# Sign in using the Automation Account managed identity.
Connect-AutomationAzure

# Log exclusion settings so the job output clearly shows what was intentionally skipped.
Write-Log "Excluded subscription IDs: $(@($ExcludedSubscriptionIdsNormalized) -join ', ')"
Write-Log "Excluded resource group names: $(@($ExcludedResourceGroupsNormalized) -join ', ')"
Write-Log "Excluded resource group IDs: $(@($ExcludedResourceGroupIdsNormalized) -join ', ')"

# Initialize counters that summarize what happened during the run.
# These are written at the end so operators can see the full picture:
#   - what was scanned
#   - what was skipped
#   - what remediation starts succeeded
#   - what remediation starts failed
[int]$SuccessfulRemediationCount = 0
[int]$FailedRemediationCount = 0
[int]$SkippedExcludedSubscriptionCount = 0
[int]$SkippedExcludedResourceGroupCount = 0
[int]$TotalResourceGroupsScannedCount = 0
[int]$TotalInitiativeAssignmentsScannedCount = 0
[int]$SkippedNonRemediatableEffectCount = 0
[int]$SkippedExistingRemediationCount = 0
[int]$WhatIfPlannedRemediationCount = 0

# Query only enabled subscriptions. Disabled subscriptions are irrelevant for remediation.
$enabledSubscriptions = Get-AzSubscription | Where-Object { $_.State -eq 'Enabled' }
Write-Log "Found $($enabledSubscriptions.Count) enabled subscription(s)."

foreach ($subscription in $enabledSubscriptions) {
    if (Test-IsExcludedSubscription -SubscriptionId $subscription.Id) {
        $SkippedExcludedSubscriptionCount++
        Write-Log "Skipping excluded subscription $($subscription.Name) [$($subscription.Id)]"
        continue
    }

    Write-Log "Processing subscription $($subscription.Name) [$($subscription.Id)]"
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null

    $resourceGroups = Get-AzResourceGroup
    Write-Log "Found $($resourceGroups.Count) resource group(s) in subscription $($subscription.Name)."

    foreach ($rg in $resourceGroups) {
        $rgId = $rg.ResourceId
        $rgName = $rg.ResourceGroupName

        if (Test-IsExcludedResourceGroup -ResourceGroupName $rgName -ResourceGroupId $rgId) {
            $SkippedExcludedResourceGroupCount++
            Write-Log "Skipping excluded resource group $rgName [$rgId]"
            continue
        }

        $TotalResourceGroupsScannedCount++
        Write-Log "Scanning resource group $rgName"

        # Retrieve only policy assignments at the resource group scope, then filter to:
        #   1. assignments whose explicit scope equals the resource group ID, and
        #   2. assignments that point to an initiative (policy set definition), not a single policy.
        # This intentionally ignores inherited assignments from a parent MG/subscription scope.
        $assignments = Get-AzPolicyAssignment -Scope $rgId | Where-Object {
            $_.Properties.Scope -eq $rgId -and
            $_.Properties.PolicyDefinitionId -match '/policySetDefinitions/'
        }

        if (-not $assignments) {
            Write-Log "No direct initiative assignments found at resource group scope for $rgName."
            continue
        }

        foreach ($assignment in $assignments) {
            $TotalInitiativeAssignmentsScannedCount++
            $assignmentId = $assignment.ResourceId
            $assignmentName = $assignment.Name
            $policySetId = $assignment.Properties.PolicyDefinitionId

            Write-Log "Processing initiative assignment $assignmentName"

            try {
                # Load the initiative definition so we can map each member policyDefinitionId
                # to its initiative member policyDefinitionReferenceId.
                # This mapping is critical because remediation for initiative members requires
                # the reference ID, not the raw policy definition ID.
                $initiative = Get-AzPolicySetDefinition -Id $policySetId -ErrorAction Stop
            }
            catch {
                Write-Log "Failed to load initiative definition for $assignmentName. $($_.Exception.Message)" 'ERROR'
                continue
            }

            $initiativeMembers = @($initiative.Properties.PolicyDefinitions)
            if (-not $initiativeMembers) {
                Write-Log "Initiative $assignmentName has no member policy definitions." 'WARN'
                continue
            }

            try {
                # Query policy states only for the current assignment and only for non-compliant results.
                # This prevents the runbook from accidentally trying to remediate policies that belong
                # to another assignment in the same resource group.
                $nonCompliantStates = Get-AzPolicyState -Filter "PolicyAssignmentId eq '$assignmentId' and ComplianceState eq 'NonCompliant'" -ErrorAction Stop
            }
            catch {
                Write-Log "Failed to query policy states for assignment $assignmentName. $($_.Exception.Message)" 'ERROR'
                continue
            }

            if (-not $nonCompliantStates) {
                Write-Log "No non-compliant resources found for assignment $assignmentName."
                continue
            }

            # Group by policy definition so one remediation task is attempted per initiative member,
            # not once per individual non-compliant resource.
            $groupedPolicies = $nonCompliantStates |
                Where-Object { $_.PolicyDefinitionId } |
                Group-Object -Property PolicyDefinitionId

            foreach ($group in $groupedPolicies) {
                $memberPolicyDefinitionId = $group.Name

                # Match the policy state's policyDefinitionId to the corresponding initiative member.
                $matchingMember = $initiativeMembers | Where-Object { $_.policyDefinitionId -eq $memberPolicyDefinitionId } | Select-Object -First 1

                if (-not $matchingMember) {
                    Write-Log "Could not map policy definition $memberPolicyDefinitionId to a member of initiative $assignmentName." 'WARN'
                    continue
                }

                $policyDefinitionReferenceId = $matchingMember.policyDefinitionReferenceId
                if ([string]::IsNullOrWhiteSpace($policyDefinitionReferenceId)) {
                    Write-Log "Missing policyDefinitionReferenceId for member policy $memberPolicyDefinitionId in initiative $assignmentName." 'WARN'
                    continue
                }

                # Only start remediation for policy effects that actually support remediation.
                $effect = Get-PolicyEffectFromDefinitionId -PolicyDefinitionId $memberPolicyDefinitionId
                if ($effect -notin (Get-RemediatableEffects)) {
                    $SkippedNonRemediatableEffectCount++
                    Write-Log "Skipping member $policyDefinitionReferenceId because effect '$effect' is not remediatable."
                    continue
                }

                # Avoid duplicate work by checking whether a remediation already exists for this
                # assignment/member combination at the current resource group scope.
                $existing = Get-ExistingActiveRemediation -Scope $rgId -PolicyAssignmentId $assignmentId -PolicyDefinitionReferenceId $policyDefinitionReferenceId
                if ($existing) {
                    $SkippedExistingRemediationCount++
                    Write-Log "Skipping member $policyDefinitionReferenceId because remediation task '$($existing.Name)' already exists with state '$($existing.ProvisioningState)'."
                    continue
                }

                # Build a remediation task name that is unique enough for repeated runs and safe
                # for Azure naming requirements.
                $safeRef = ($policyDefinitionReferenceId -replace '[^a-zA-Z0-9-]','-')
                $safeAssignmentName = ($assignmentName -replace '[^a-zA-Z0-9-]','-')
                $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $remediationName = ("remediate-{0}-{1}-{2}" -f $safeAssignmentName, $safeRef, $timestamp)
                if ($remediationName.Length -gt 80) {
                    $remediationName = $remediationName.Substring(0,80)
                }

                if ($WhatIfOnly) {
                    $WhatIfPlannedRemediationCount++
                    Write-Log "[WhatIf] Would start remediation '$remediationName' for assignment '$assignmentName' member '$policyDefinitionReferenceId' in RG '$rgName'."
                    continue
                }

                try {
                    # Start remediation for the specific initiative member within the current
                    # resource group scope.
                    Start-AzPolicyRemediation `
                        -Name $remediationName `
                        -PolicyAssignmentId $assignmentId `
                        -PolicyDefinitionReferenceId $policyDefinitionReferenceId `
                        -ResourceGroupName $rgName `
                        -ErrorAction Stop | Out-Null

                    $SuccessfulRemediationCount++
                    Write-Log "Started remediation '$remediationName' for member '$policyDefinitionReferenceId'."
                }
                catch {
                    $FailedRemediationCount++
                    Write-Log "Failed to start remediation for assignment '$assignmentName', member '$policyDefinitionReferenceId'. $($_.Exception.Message)" 'ERROR'
                }
            }
        }
    }
}

# Final summary output for the runbook. These values show the overall flow of the job:
#   - how many scopes were skipped by exclusion
#   - how many resource groups and initiative assignments were scanned
#   - how many candidate remediations were skipped because they were not remediatable
#     or because an active remediation already existed
#   - how many starts were planned in WhatIf mode
#   - how many remediation task starts succeeded or failed
Write-Log "Total excluded subscriptions skipped: $SkippedExcludedSubscriptionCount"
Write-Log "Total excluded resource groups skipped: $SkippedExcludedResourceGroupCount"
Write-Log "Total resource groups scanned: $TotalResourceGroupsScannedCount"
Write-Log "Total initiative assignments scanned: $TotalInitiativeAssignmentsScannedCount"
Write-Log "Total skipped due to non-remediatable effects: $SkippedNonRemediatableEffectCount"
Write-Log "Total skipped due to existing remediation: $SkippedExistingRemediationCount"
Write-Log "Total WhatIf remediations planned: $WhatIfPlannedRemediationCount"
Write-Log "Total successful remediation starts: $SuccessfulRemediationCount"
Write-Log "Total failed remediation starts: $FailedRemediationCount"
Write-Log 'Runbook completed.'
