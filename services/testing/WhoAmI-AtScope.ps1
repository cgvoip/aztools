<#
.SYNOPSIS
  Shows your principal ObjectId and effective role assignments at a given scope (and parents).
.DESCRIPTION
  Useful to validate RBAC from the menu. Defaults to current subscription scope.
.PARAMETER ResourceGroupName
  Optional RG name. If provided, scope is /subscriptions/<sub>/resourceGroups/<rg>.
.PARAMETER Scope
  Optional explicit resource ID scope (overrides ResourceGroupName if supplied).
#>
[CmdletBinding()]
param(
  [string]$ResourceGroupName,
  [string]$Scope
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CurrentPrincipalId {
  $ctx = Get-AzContext
  if (-not $ctx) { throw "No Az context." }
  $tenantId = $ctx.Tenant.Id
  $acct = $ctx.Account

  switch ($acct.Type) {
    'User' {
      $u = $null
      try { $u = Get-AzADUser -SignedIn -TenantId $tenantId -ErrorAction Stop } catch { }
      if (-not $u) { try { $u = Get-AzADUser -SignedIn -ErrorAction Stop } catch { }
      }
      if ($u) { return ($u | Select-Object -First 1).Id }

      $u2 = $null
      try { $u2 = Get-AzADUser -UserPrincipalName $acct.Id -TenantId $tenantId -ErrorAction Stop } catch { }
      if (-not $u2) { try { $u2 = Get-AzADUser -UserPrincipalName $acct.Id -ErrorAction Stop } catch { } }
      if ($u2) { return ($u2 | Select-Object -First 1).Id }
      throw "Unable to resolve user objectId in tenant $tenantId."
    }
    'ServicePrincipal' {
      $sp = $null
      try { $sp = Get-AzADServicePrincipal -ApplicationId $acct.Id -TenantId $tenantId -ErrorAction Stop } catch { }
      if (-not $sp) { try { $sp = Get-AzADServicePrincipal -ApplicationId $acct.Id -ErrorAction Stop } catch { } }
      if ($sp) { return ($sp | Select-Object -First 1).Id }

      if ($acct.ExtendedProperties.ContainsKey('ServicePrincipalObjectId')) {
        return $acct.ExtendedProperties['ServicePrincipalObjectId']
      }
      throw "Unable to resolve service principal objectId."
    }
    default {
      $sp = $null
      try { $sp = Get-AzADServicePrincipal -DisplayName $acct.Id -TenantId $tenantId -ErrorAction Stop } catch { }
      if (-not $sp) { try { $sp = Get-AzADServicePrincipal -DisplayName $acct.Id -ErrorAction Stop } catch { } }
      if ($sp) { return ($sp | Select-Object -First 1).Id }
      if ($acct.Id -match '^[0-9a-fA-F-]{36}$') { return $acct.Id }
      throw "Unsupported account type '$($acct.Type)'."
    }
  }
}

function Get-ParentScopes {
  param([Parameter(Mandatory)][string]$Scope)
  $list = New-Object System.Collections.Generic.List[string]
  $list.Add($Scope) | Out-Null
  if ($Scope -match '^/subscriptions/([^/]+)/resourceGroups/[^/]+') {
    $subId = $Matches[1]
    $list.Add("/subscriptions/$subId") | Out-Null
  }
  return $list
}

# Determine scope
$ctx = Get-AzContext
$subId = $ctx.Subscription.Id

if (-not $Scope) {
  if ($ResourceGroupName) {
    $Scope = "/subscriptions/$subId/resourceGroups/$ResourceGroupName"
  } else {
    $Scope = "/subscriptions/$subId"
  }
}

$principalId = Get-CurrentPrincipalId

Write-Host "Principal ObjectId : $principalId"
Write-Host "Scope              : $Scope"
Write-Host ""

$allRoles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($s in (Get-ParentScopes -Scope $Scope)) {
  Write-Host "== Assignments @ $s =="
  $assign = @(Get-AzRoleAssignment -ObjectId $principalId -Scope $s -ErrorAction SilentlyContinue)
  if ($assign.Count -eq 0) {
    Write-Host "(none)" -ForegroundColor DarkGray
  } else {
    $assign |
      Select-Object RoleDefinitionName, Scope, DisplayName, SignInName |
      Sort-Object RoleDefinitionName |
      Format-Table -AutoSize
    foreach ($a in $assign) { [void]$allRoles.Add($a.RoleDefinitionName) }
  }
  Write-Host ""
}

Write-Host "Effective roles (at or above scope):"
if ($allRoles.Count -eq 0) {
  Write-Host "(none)" -ForegroundColor Yellow
} else {
  $allRoles | Sort-Object | ForEach-Object { "  - $_" }
}
