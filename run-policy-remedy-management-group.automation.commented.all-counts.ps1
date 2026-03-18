<#
.SYNOPSIS
    Azure Automation runbook that starts remediation tasks only for individual policy
    assignments that are directly assigned at the Azure Management Group scope.

.DESCRIPTION
    This runbook:
      1. Authenticates to Azure using the Automation Account managed identity.
      2. Enumerates available management groups.
      3. Finds individual policy assignments that are directly scoped to each management group.
      4. Looks for non-compliant policy states for that exact policy assignment.
      5. Checks whether the assigned policy effect supports remediation.
      6. Starts remediation only for remediatable policy effects:
         - deployIfNotExists
         - modify
      7. Skips management groups listed in the exclusion parameters.

    Important notes:
      - This script only targets single policy assignments directly assigned to the
        management group. It intentionally skips initiatives and inherited assignments.
      - This script only starts remediation tasks for policies that support remediation.
      - This script avoids creating duplicate remediation tasks when a matching active
        remediation already exists.

.PARAMETER WhatIfOnly
    When supplied, the runbook logs what it would do but does not start remediation.

.PARAMETER ExcludedManagementGroupIds
    Array of management group IDs to exclude from remediation processing.

.PARAMETER ExcludedManagementGroupNames
    Array of management group display names to exclude from remediation processing.
    Matching is by management group display name only.

.EXAMPLE
    .\run-policy-remedy-management-group.automation.commented.all-counts.ps1 -WhatIfOnly

.EXAMPLE
    .\run-policy-remedy-management-group.automation.commented.all-counts.ps1 `
        -ExcludedManagementGroupIds @('contoso-platform','contoso-sandbox') `
        -ExcludedManagementGroupNames @('Platform Root MG','Sandbox MG')
#>

param(
    [switch]$WhatIfOnly,

    # Management groups listed here are skipped entirely by management group ID.
    [string[]]$ExcludedManagementGroupIds = @(),

    # Management groups with these display names are skipped.
    [string[]]$ExcludedManagementGroupNames = @()
)

$ErrorActionPreference = 'Stop'

# Normalize exclusion input once so comparisons are fast and case-insensitive.
$ExcludedManagementGroupIdsNormalized = @($ExcludedManagementGroupIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToLowerInvariant() })
$ExcludedManagementGroupNamesNormalized = @($ExcludedManagementGroupNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToLowerInvariant() })

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
        then signs in with the runbook's managed identity.
    #>
    Disable-AzContextAutosave -Scope Process | Out-Null

    try {
        $ctx = (Connect-AzAccount -Identity).Context
        if (-not $ctx) {
            throw 'Connect-AzAccount -Identity returned no context.'
        }

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
    #>
    @('deployIfNotExists','modify')
}

function Get-PolicyEffectFromDefinitionId {
    <#
    .SYNOPSIS
        Reads a policy definition and returns its effect.

    .DESCRIPTION
        Single-policy remediation only makes sense for remediatable policy effects.
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
        Checks whether a remediation task already exists for the same assignment.

    .DESCRIPTION
        Prevents duplicate remediation tasks from being created when one already exists for:
          - the same scope
          - the same policy assignment

        Tasks in accepted, running, evaluating, or succeeded states are treated as already present.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Scope,
        [Parameter(Mandatory=$true)][string]$PolicyAssignmentId
    )

    try {
        $existing = Get-AzPolicyRemediation -Scope $Scope -ErrorAction SilentlyContinue
        if (-not $existing) { return $null }

        return $existing | Where-Object {
            $_.PolicyAssignmentId -eq $PolicyAssignmentId -and
            $_.ProvisioningState -in @('Accepted','Running','Evaluating','Succeeded')
        } | Select-Object -First 1
    }
    catch {
        Write-Log "Could not enumerate remediation tasks at scope $Scope. $($_.Exception.Message)" 'WARN'
        return $null
    }
}

function Test-IsExcludedManagementGroup {
    <#
    .SYNOPSIS
        Returns $true when the current management group matches either exclusion list.

    .DESCRIPTION
        A management group can be excluded by management group ID or by display name.
        Use the ID exclusion when you need exact targeting.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$ManagementGroupId,
        [Parameter(Mandatory=$true)][string]$ManagementGroupDisplayName
    )

    $mgIdNormalized = $ManagementGroupId.Trim().ToLowerInvariant()
    $mgNameNormalized = $ManagementGroupDisplayName.Trim().ToLowerInvariant()

    return (($mgIdNormalized -in $ExcludedManagementGroupIdsNormalized) -or ($mgNameNormalized -in $ExcludedManagementGroupNamesNormalized))
}

# Validate that the runbook has the modules it needs before doing anything else.
Ensure-Module -Name Az.Accounts
Ensure-Module -Name Az.Resources
Ensure-Module -Name Az.PolicyInsights

# Sign in using the Automation Account managed identity.
Connect-AutomationAzure

# Log exclusion settings so the job output clearly shows what was intentionally skipped.
Write-Log "Excluded management group IDs: $(@($ExcludedManagementGroupIdsNormalized) -join ', ')"
Write-Log "Excluded management group names: $(@($ExcludedManagementGroupNamesNormalized) -join ', ')"

# Initialize counters that summarize what happened during the run.
[int]$SuccessfulRemediationCount = 0
[int]$FailedRemediationCount = 0
[int]$SkippedExcludedManagementGroupCount = 0
[int]$TotalManagementGroupsScannedCount = 0
[int]$TotalPolicyAssignmentsScannedCount = 0
[int]$SkippedInitiativeAssignmentCount = 0
[int]$SkippedNonRemediatableEffectCount = 0
[int]$SkippedExistingRemediationCount = 0
[int]$WhatIfPlannedRemediationCount = 0

# Retrieve management groups visible to the runbook identity.
$managementGroups = Get-AzManagementGroup -Expand -Recurse
Write-Log "Found $($managementGroups.Count) management group(s)."

foreach ($mg in $managementGroups) {
    $mgId = $mg.Name
    $mgDisplayName = if ([string]::IsNullOrWhiteSpace($mg.DisplayName)) { $mg.Name } else { $mg.DisplayName }
    $mgScope = "/providers/Microsoft.Management/managementGroups/$mgId"

    if (Test-IsExcludedManagementGroup -ManagementGroupId $mgId -ManagementGroupDisplayName $mgDisplayName) {
        $SkippedExcludedManagementGroupCount++
        Write-Log "Skipping excluded management group $mgDisplayName [$mgId]"
        continue
    }

    $TotalManagementGroupsScannedCount++
    Write-Log "Scanning management group $mgDisplayName [$mgId]"

    # Retrieve only policy assignments at the management group scope, then filter to:
    #   1. assignments whose explicit scope equals the management group scope, and
    #   2. assignments that point to a single policy definition, not an initiative.
    # This intentionally ignores inherited assignments and initiatives.
    try {
        $assignments = Get-AzPolicyAssignment -Scope $mgScope -ErrorAction Stop | Where-Object {
            $_.Properties.Scope -eq $mgScope -and
            $_.Properties.PolicyDefinitionId -match '/policyDefinitions/'
        }
    }
    catch {
        Write-Log "Failed to enumerate policy assignments for management group $mgDisplayName [$mgId]. $($_.Exception.Message)" 'ERROR'
        continue
    }

    if (-not $assignments) {
        Write-Log "No direct single-policy assignments found at management group scope for $mgDisplayName [$mgId]."
        continue
    }

    foreach ($assignment in $assignments) {
        $assignmentId = $assignment.ResourceId
        $assignmentName = $assignment.Name
        $policyDefinitionId = $assignment.Properties.PolicyDefinitionId

        if ($policyDefinitionId -match '/policySetDefinitions/') {
            $SkippedInitiativeAssignmentCount++
            Write-Log "Skipping initiative assignment $assignmentName because this runbook only remediates individual policy assignments."
            continue
        }

        $TotalPolicyAssignmentsScannedCount++
        Write-Log "Processing policy assignment $assignmentName"

        try {
            # Query policy states only for the current assignment and only for non-compliant results.
            # This prevents the runbook from accidentally trying to remediate another assignment.
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

        # Only start remediation for policy effects that actually support remediation.
        $effect = Get-PolicyEffectFromDefinitionId -PolicyDefinitionId $policyDefinitionId
        if ($effect -notin (Get-RemediatableEffects)) {
            $SkippedNonRemediatableEffectCount++
            Write-Log "Skipping assignment $assignmentName because effect '$effect' is not remediatable."
            continue
        }

        # Avoid duplicate work by checking whether a remediation already exists for this
        # assignment at the current management group scope.
        $existing = Get-ExistingActiveRemediation -Scope $mgScope -PolicyAssignmentId $assignmentId
        if ($existing) {
            $SkippedExistingRemediationCount++
            Write-Log "Skipping assignment $assignmentName because remediation task '$($existing.Name)' already exists with state '$($existing.ProvisioningState)'."
            continue
        }

        # Build a remediation task name that is unique enough for repeated runs and safe
        # for Azure naming requirements.
        $safeAssignmentName = ($assignmentName -replace '[^a-zA-Z0-9-]','-')
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $remediationName = ("remediate-{0}-{1}" -f $safeAssignmentName, $timestamp)
        if ($remediationName.Length -gt 80) {
            $remediationName = $remediationName.Substring(0,80)
        }

        if ($WhatIfOnly) {
            $WhatIfPlannedRemediationCount++
            Write-Log "[WhatIf] Would start remediation '$remediationName' for assignment '$assignmentName' in management group '$mgDisplayName'."
            continue
        }

        try {
            # Start remediation for the specific individual policy assignment within the current
            # management group scope.
            Start-AzPolicyRemediation `
                -Name $remediationName `
                -PolicyAssignmentId $assignmentId `
                -ManagementGroupName $mgId `
                -ErrorAction Stop | Out-Null

            $SuccessfulRemediationCount++
            Write-Log "Started remediation '$remediationName' for assignment '$assignmentName'."
        }
        catch {
            $FailedRemediationCount++
            Write-Log "Failed to start remediation for assignment '$assignmentName'. $($_.Exception.Message)" 'ERROR'
        }
    }
}

# Final summary output for the runbook.
Write-Log "Total excluded management groups skipped: $SkippedExcludedManagementGroupCount"
Write-Log "Total management groups scanned: $TotalManagementGroupsScannedCount"
Write-Log "Total individual policy assignments scanned: $TotalPolicyAssignmentsScannedCount"
Write-Log "Total initiative assignments skipped: $SkippedInitiativeAssignmentCount"
Write-Log "Total skipped due to non-remediatable effects: $SkippedNonRemediatableEffectCount"
Write-Log "Total skipped due to existing remediation: $SkippedExistingRemediationCount"
Write-Log "Total WhatIf remediations planned: $WhatIfPlannedRemediationCount"
Write-Log "Total successful remediation starts: $SuccessfulRemediationCount"
Write-Log "Total failed remediation starts: $FailedRemediationCount"
Write-Log 'Runbook completed.'
