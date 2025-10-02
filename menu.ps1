# menu.ps1
# Menu-driven Azure support launcher with:
# - Robust config (with defaults, comments allowed)
# - Tenant-first login, then subscription selection (works with older Az versions)
# - RBAC gating per action (Reader/Contributor/etc.) at declared scope
# - Arrow-key UI (Up/Down/Home/End/Enter/Esc; F=filter; I=details)
# - Safe array handling (no single-item unwrap surprises)
# - Correct script invocation (array arg expansion; optional new window)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ===========================
# Paths
# ===========================
$Root        = Split-Path -Parent $MyInvocation.MyCommand.Path
$ServicesDir = Join-Path $Root 'services'
$LogsDir     = Join-Path $Root 'logs'
if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir | Out-Null }

# ===========================
# Logging
# ===========================
function Write-Log {
  param([string]$Message,[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "$timestamp [$Level] $Message"
  $logFile = Join-Path $LogsDir ("run-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
  Add-Content -Path $logFile -Value $line
  Write-Host $line
}

# ===========================
# Config (defaults + merge; supports comments and trailing commas)
# ===========================
$DefaultConfig = [pscustomobject]@{
  AzLogin               = $true
  DefaultTenantId       = $null
  DefaultSubscriptionId = $null
  NewWindowForScripts   = $false
  HideLockedActions     = $true
}

function Load-JsonFile {
  param([Parameter(Mandatory)][string]$Path)
  $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
  # strip // and /* */ comments; and trailing commas before ] or }
  $raw = $raw -replace '(?m)^\s*//.*$',''
  $raw = $raw -replace '/\*.*?\*/',''
  $raw = $raw -replace ',(\s*[}\]])','$1'
  return $raw | ConvertFrom-Json -Depth 20
}

function Merge-Config {
  param([pscustomobject]$Base,[pscustomobject]$Override)
  $merged = $Base.PSObject.Copy()
  foreach ($p in $Override.PSObject.Properties) {
    if ($merged.PSObject.Properties.Name -contains $p.Name) {
      $merged.$($p.Name) = $p.Value
    } else {
      $merged | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
    }
  }
  return $merged
}

function Load-Config {
  $candidates = @()
  if ($env:CONFIG_PATH) { $candidates += $env:CONFIG_PATH }
  $candidates += (Join-Path $Root 'config.json')
  $candidates  = @($candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) })

  if (-not $candidates -or @($candidates).Count -eq 0) {
    Write-Log "No config.json found; using defaults." 'WARN'
    return $DefaultConfig
  }

  $path = ($candidates | Select-Object -First 1)
  try {
    $loaded = Load-JsonFile -Path $path
    if (-not ($loaded -is [pscustomobject])) { $loaded = [pscustomobject]$loaded }
    $cfg = Merge-Config -Base $DefaultConfig -Override $loaded
    Write-Log "Loaded config from $path"
    return $cfg
  } catch {
    Write-Log "Failed to parse config at $path. Using defaults. $_" 'ERROR'
    return $DefaultConfig
  }
}

$Config = Load-Config
Write-Log ("Effective config: " + ($Config | ConvertTo-Json -Compress))

# ===========================
# Arrow-key UI
# ===========================
function Show-ArrowMenu {
  param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][object[]]$Items,
    [switch]$ShowLegend
  )
  $idx = 0
  $filter = ''
  [Console]::CursorVisible = $false
  try {
    while ($true) {
      Clear-Host
      Write-Host "=== $Title ==="
      if ($ShowLegend) {
        Write-Host "[↑/↓] Move   [Enter] Select   [Esc] Back   [F] Filter   [I] Info   [Home/End] Jump" -ForegroundColor DarkGray
      }

      $visible = if ([string]::IsNullOrWhiteSpace($filter)) { @($Items) } else { @($Items | Where-Object { $_.Label -like "*$filter*" }) }
      if (-not $visible) { $visible = @() }

      if ($visible.Count -eq 0) {
        Write-Host "(No items match filter '$filter')" -ForegroundColor Yellow
      } else {
        if ($idx -ge $visible.Count) { $idx = $visible.Count - 1 }
        for ($i=0; $i -lt $visible.Count; $i++) {
          $prefix = if ($i -eq $idx) { '>' } else { ' ' }
          $label  = $visible[$i].Label
          if (-not $visible[$i].Enabled) { $label = "🔒 $label" }
          if ($i -eq $idx) { Write-Host ("$prefix $label") -ForegroundColor Cyan } else { Write-Host ("$prefix $label") }
        }
      }

      if ($filter) { Write-Host ("Filter: $filter") -ForegroundColor DarkGray }

      $key = [Console]::ReadKey($true)
      switch ($key.Key) {
        'UpArrow'   { if ($idx -gt 0) { $idx-- } }
        'DownArrow' { if ($idx -lt ($visible.Count-1)) { $idx++ } }
        'Home'      { $idx = 0 }
        'End'       { if ($visible.Count -gt 0) { $idx = $visible.Count-1 } }
        'Enter'     { if ($visible.Count -gt 0) { return $visible[$idx] } }
        'Escape'    { return $null }
        default {
          if ($key.Key -eq 'F') {
            $filter = ''
            while ($true) {
              Clear-Host
              Write-Host "=== $Title (type to filter, Enter=apply, Esc=cancel) ==="
              Write-Host $filter -NoNewline
              $k = [Console]::ReadKey($true)
              if     ($k.Key -eq 'Enter')    { break }
              elseif ($k.Key -eq 'Escape')   { $filter = ''; break }
              elseif ($k.Key -eq 'Backspace'){ if ($filter.Length -gt 0) { $filter = $filter.Substring(0,$filter.Length-1) } }
              else   { if ($k.KeyChar) { $filter += $k.KeyChar } }
            }
          } elseif ($key.Key -eq 'I') {
            if ($visible.Count -gt 0) {
              Clear-Host
              Write-Host "=== Details ===" -ForegroundColor Green
              ($visible[$idx].Detail | Out-String).Trim() | Write-Host
              Write-Host ""
              Write-Host "Press any key..."
              [Console]::ReadKey($true) | Out-Null
            }
          }
        }
      }
    }
  } finally { [Console]::CursorVisible = $true }
}

# ===========================
# Azure auth: tenant then subscription (compatible across Az versions)
# ===========================
function Select-TenantInteractive {
  param([string]$PreferredTenantId)

  $tenants = @(Get-AzTenant -ErrorAction Stop)
  if ($tenants.Count -eq 0) { throw "No tenants available for this account." }

  $chosen = $null
  if ($PreferredTenantId) {
    $chosen = $tenants | Where-Object { $_.TenantId -eq $PreferredTenantId } | Select-Object -First 1
    if (-not $chosen) { Write-Log "Preferred tenant $PreferredTenantId not found; prompting…" 'WARN' }
  }

  if (-not $chosen) {
    $items = $tenants | ForEach-Object {
      [pscustomobject]@{
        Label   = "$($_.DisplayName) ($($_.TenantId))"
        Tag     = $_
        Enabled = $true
        Detail  = "DefaultDomain: $($_.DefaultDomain)`nTenantId: $($_.TenantId)"
      }
    }
    $items += [pscustomobject]@{ Label='(Exit)'; Tag='__exit__'; Enabled=$true; Detail='' }
    $pick = Show-ArrowMenu -Title 'Select tenant' -Items $items -ShowLegend
    if (-not $pick -or $pick.Tag -eq '__exit__') { throw "User cancelled tenant selection." }
    $chosen = $pick.Tag
  }

  try {
    Connect-AzAccount -TenantId $chosen.TenantId -ErrorAction Stop | Out-Null
  } catch {
    Write-Warning "Interactive login failed in tenant $($chosen.TenantId). Retrying with device code…"
    Connect-AzAccount -TenantId $chosen.TenantId -UseDeviceAuthentication -ErrorAction Stop | Out-Null
  }
  return $chosen.TenantId
}

function Ensure-AzContext {
  $AzLoginEnabled = $true
  if ($null -ne $Config -and $Config.PSObject.Properties['AzLogin']) {
    $AzLoginEnabled = [bool]$Config.AzLogin
  }
  if (-not $AzLoginEnabled) { return }

  # 1) Tenant
  $tenantId = Select-TenantInteractive -PreferredTenantId $Config.DefaultTenantId
  Write-Log "Active tenant: $tenantId"

  # 2) Subscriptions in that tenant
  $subs = @( Get-AzSubscription -TenantId $tenantId -ErrorAction SilentlyContinue )
  if (-not $subs -or $subs.Count -eq 0) {
    # fallback for older Az: filter client-side
    $subs = @( Get-AzSubscription -ErrorAction Stop | Where-Object { $_.TenantId -eq $tenantId } )
  }
  if ($subs.Count -eq 0) { throw "No subscriptions in tenant $tenantId." }

  $targetSub = $null
  if ($Config.DefaultSubscriptionId) {
    $targetSub = $subs | Where-Object { $_.Id -eq $Config.DefaultSubscriptionId } | Select-Object -First 1
    if (-not $targetSub) { Write-Log "DefaultSubscriptionId not in tenant $tenantId; ignoring." 'WARN' }
  }
  if (-not $targetSub) {
    $items = $subs | ForEach-Object {
      [pscustomobject]@{
        Label   = "$($_.Name) ($($_.Id))"
        Tag     = $_
        Enabled = $true
        Detail  = "State: $($_.State)`nTenant: $($_.TenantId)"
      }
    }
    $pick = Show-ArrowMenu -Title 'Select subscription' -Items $items -ShowLegend
    if (-not $pick) { throw "User cancelled subscription selection." }
    $targetSub = $pick.Tag
  }

  # 3) Set context (no -TenantId here for older Az)
  try {
    Set-AzContext -SubscriptionId $targetSub.Id | Out-Null
  } catch {
    Select-AzSubscription -SubscriptionId $targetSub.Id | Out-Null
  }

  $ctx = Get-AzContext
  if (-not $ctx -or -not $ctx.Subscription -or -not $ctx.Subscription.Id) {
    throw "Failed to establish Az context for sub $($targetSub.Id) in tenant $tenantId."
  }
  Write-Log "Active subscription: $($ctx.Subscription.Name) ($($ctx.Subscription.Id))"
}

# ===========================
# RBAC helpers
# ===========================
function Get-CurrentPrincipalId {
  $ctx = Get-AzContext
  if (-not $ctx) { throw "No Az context." }
  $tenantId = $ctx.Tenant.Id
  $acct = $ctx.Account

  switch ($acct.Type) {
    'User' {
      $u = $null
      try { $u = Get-AzADUser -SignedIn -TenantId $tenantId -ErrorAction Stop } catch { }
      if (-not $u) { try { $u = Get-AzADUser -SignedIn -ErrorAction Stop } catch { } }
      if ($u) { return ($u | Select-Object -First 1).Id }

      $u2 = $null
      try { $u2 = Get-AzADUser -UserPrincipalName $acct.Id -TenantId $tenantId -ErrorAction Stop } catch { }
      if (-not $u2) { try { $u2 = Get-AzADUser -UserPrincipalName $acct.Id -ErrorAction Stop } catch { } }
      if ($u2) { return ($u2 | Select-Object -First 1).Id }
      throw "Unable to resolve signed-in user objectId in tenant $tenantId."
    }
    'ServicePrincipal' {
      $sp = $null
      try { $sp = Get-AzADServicePrincipal -ApplicationId $acct.Id -TenantId $tenantId -ErrorAction Stop } catch { }
      if (-not $sp) { try { $sp = Get-AzADServicePrincipal -ApplicationId $acct.Id -ErrorAction Stop } catch { } }
      if ($sp) { return ($sp | Select-Object -First 1).Id }

      if ($acct.ExtendedProperties.ContainsKey('ServicePrincipalObjectId')) {
        return $acct.ExtendedProperties['ServicePrincipalObjectId']
      }
      throw "Unable to resolve service principal objectId for AppId $($acct.Id) in tenant $tenantId."
    }
    default {
      $sp = $null
      try { $sp = Get-AzADServicePrincipal -DisplayName $acct.Id -TenantId $tenantId -ErrorAction Stop } catch { }
      if (-not $sp) { try { $sp = Get-AzADServicePrincipal -DisplayName $acct.Id -ErrorAction Stop } catch { } }
      if ($sp) { return ($sp | Select-Object -First 1).Id }
      if ($acct.Id -match '^[0-9a-fA-F-]{36}$') { return $acct.Id }
      throw "Unsupported account type '$($acct.Type)'; cannot resolve principal objectId."
    }
  }
}

function Resolve-ScopeResourceId {
  param(
    [object]$ScopeDef,  # allow $null
    [Parameter(Mandatory)][string]$DefaultSubscriptionId
  )
  if ($null -eq $ScopeDef -or ($ScopeDef -is [string] -and [string]::IsNullOrWhiteSpace($ScopeDef))) {
    return "/subscriptions/$DefaultSubscriptionId"
  }
  if ($ScopeDef -is [string]) {
    if     ($ScopeDef -match '^/subscriptions/') { return $ScopeDef }
    elseif ($ScopeDef -eq 'subscription')         { return "/subscriptions/$DefaultSubscriptionId" }
    else                                          { return "/subscriptions/$DefaultSubscriptionId/resourceGroups/$ScopeDef" }
  }
  $type = $ScopeDef.type
  switch ($type) {
    'subscription' { return "/subscriptions/$DefaultSubscriptionId" }
    'resourceGroup' {
      $rg = [string]$ScopeDef.name
      if ([string]::IsNullOrWhiteSpace($rg)) { throw "scope.resourceGroup requires 'name'." }
      return "/subscriptions/$DefaultSubscriptionId/resourceGroups/$rg"
    }
    default {
      if ($ScopeDef.resourceId) { return [string]$ScopeDef.resourceId }
      throw "Unsupported scope: $($ScopeDef | ConvertTo-Json -Compress)"
    }
  }
}

function Get-ParentScopes {
  param([Parameter(Mandatory)][string]$Scope)
  $scopes = New-Object System.Collections.Generic.List[string]
  $scopes.Add($Scope) | Out-Null
  if ($Scope -match '^/subscriptions/[^/]+/resourceGroups/[^/]+') {
    $subId = ($Scope -replace '^/subscriptions/([^/]+).*','$1')
    $scopes.Add("/subscriptions/$subId") | Out-Null
  }
  return $scopes
}

function Get-EffectiveRolesForPrincipal {
  param([Parameter(Mandatory)][string]$PrincipalId,[Parameter(Mandatory)][string]$Scope)
  $roles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($s in (Get-ParentScopes -Scope $Scope)) {
    try {
      $assign = @(Get-AzRoleAssignment -ObjectId $PrincipalId -Scope $s -ErrorAction SilentlyContinue)
      foreach ($a in $assign) { [void]$roles.Add($a.RoleDefinitionName) }
    } catch { }
  }
  return ,$roles
}
function Test-RequiredRoles {
  param(
    [string[]]$RequiredRoles = @(),
    [Parameter(Mandatory)][string]$Scope,
    [Parameter(Mandatory)][string]$PrincipalId
  )

  if (-not $RequiredRoles -or @($RequiredRoles).Count -eq 0) {
    return [pscustomobject]@{ Allowed = $true; Missing = @(); Effective = @() }
  }

  $effective = Get-EffectiveRolesForPrincipal -PrincipalId $PrincipalId -Scope $Scope
  $missing = @()
  foreach ($r in $RequiredRoles) {
    if (-not $effective.Contains($r)) { $missing += $r }
  }

  [pscustomobject]@{
    Allowed   = ($missing.Count -eq 0)
    Missing   = $missing
    Effective = @($effective)
  }
}


# ===========================
# Actions manifest loader
# ===========================
function Load-ServiceActions {
  param([Parameter(Mandatory)][string]$ServiceFolder)

  $manifestPath = Join-Path $ServiceFolder 'actions.json'
  $actions = @()

  if (Test-Path $manifestPath) {
    try {
      $man = Load-JsonFile -Path $manifestPath  # supports comments/trailing commas
      foreach ($a in $man.actions) {
        $obj = [pscustomobject]@{
          Name          = [string]$a.name
          ScriptPath    = (Join-Path $ServiceFolder ([string]$a.script))
          Args          = @()
          SameProcess   = $false
          RequiredRoles = @($a.requiredRoles)
          ScopeDef      = $a.scope
        }
        if ($a.args)       { $obj.Args        = @($a.args | ForEach-Object { [string]$_ }) }
        if ($a.sameProcess){ $obj.SameProcess = [bool]$a.sameProcess }
        $actions += $obj
      }
      return ,$actions
    } catch {
      Write-Log "Failed to parse actions.json for '$ServiceFolder'. Falling back to *.ps1. $_" 'WARN'
    }
  }

  # Fallback: every *.ps1 is an action (no RBAC requirement)
  Get-ChildItem -Path $ServiceFolder -Filter *.ps1 -File |
    ForEach-Object {
      [pscustomobject]@{
        Name          = $_.BaseName
        ScriptPath    = $_.FullName
        Args          = @()
        SameProcess   = $true
        RequiredRoles = @()
        ScopeDef      = $null
      }
    }
}

# ===========================
# Invoke action
# ===========================
function Invoke-Action {
  param([Parameter(Mandatory)][pscustomobject]$Action)

  if (-not (Test-Path $Action.ScriptPath)) {
    Write-Host "Script not found: $($Action.ScriptPath)" -ForegroundColor Red
    return
  }

  $argLine = ($Action.Args -join ' ')
  Write-Log ("Executing: {0} {1}" -f $Action.ScriptPath, $argLine)

  $sameProcess = if ($null -ne $Action.SameProcess) { [bool]$Action.SameProcess } else { $true }

  if (-not $sameProcess -or $Config.NewWindowForScripts) {
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
    $exe  = if ($pwsh) { $pwsh } else { (Get-Command powershell).Source }
    $args = @('-NoExit','-File',"`"$($Action.ScriptPath)`"") + $Action.Args
    Start-Process -FilePath $exe -ArgumentList $args -WindowStyle Normal | Out-Null
  } else {
    & $Action.ScriptPath @($Action.Args)   # correct array expansion
  }
}

# ===========================
# Main
# ===========================
# ===========================
# Main (hardened)
# ===========================
try {
  Ensure-AzContext

  $ctx         = Get-AzContext
  $activeSubId = $ctx.Subscription.Id
  $principalId = Get-CurrentPrincipalId
  Write-Log "RBAC debug: principalId=$principalId, sub=$activeSubId"

  $ServiceFolders = @(Get-ChildItem -Path $ServicesDir -Directory | Sort-Object Name)
  if (@($ServiceFolders).Count -eq 0) { throw "No services found under $ServicesDir" }

  while ($true) {
    # --- Build services menu
    $svcItems = @(
      $ServiceFolders | ForEach-Object {
        [pscustomobject]@{ Label=$_.Name; Tag=$_; Enabled=$true; Detail='' }
      }
    )
    $svcItems += [pscustomobject]@{ Label='(Refresh services)'; Tag='__refresh__'; Enabled=$true; Detail='' }
    $svcItems += [pscustomobject]@{ Label='(Exit)';             Tag='__exit__';    Enabled=$true; Detail='' }

    $svcPick = Show-ArrowMenu -Title 'Select a service' -Items $svcItems -ShowLegend

    # Esc/back? bail cleanly BEFORE touching $serviceFolder / $rawActions
    if (-not $svcPick) { break }
    if ($svcPick.Tag -eq '__exit__')     { break }
    if ($svcPick.Tag -eq '__refresh__')  {
      $ServiceFolders = @(Get-ChildItem -Path $ServicesDir -Directory | Sort-Object Name)
      continue
    }

    # --- Only now set folder/name; validate it exists
    $serviceFolder = $svcPick.Tag.FullName
    $serviceName   = $svcPick.Tag.Name

    if (-not (Test-Path -LiteralPath $serviceFolder)) {
      Write-Log "Service folder missing: $serviceFolder" 'WARN'
      continue
    }

    # --- Always initialize $rawActions BEFORE you ever reference it
    $rawActions = @()
    try {
      $rawActions = @(Load-ServiceActions -ServiceFolder $serviceFolder)
    } catch {
      Write-Log "Load-ServiceActions failed for '$serviceFolder': $($_.Exception.Message)" 'WARN'
      $rawActions = @()
    }

    if (@($rawActions).Count -eq 0) {
      Write-Host "No actions found for service '$serviceName'." -ForegroundColor Yellow
      continue
    }

    # --- RBAC evaluation per action (safe on empty/missing requiredRoles)
    $menuActions = @()
    foreach ($a in @($rawActions)) {
      $scope = Resolve-ScopeResourceId -ScopeDef $a.ScopeDef -DefaultSubscriptionId $activeSubId
      $req   = @($a.RequiredRoles) | Where-Object { $_ -and $_.ToString().Trim() -ne '' }

      $rbac = if (@($req).Count -gt 0) {
        Test-RequiredRoles -RequiredRoles $req -Scope $scope -PrincipalId $principalId
      } else {
        [pscustomobject]@{ Allowed = $true; Missing = @(); Effective = @() }
      }

      $isAllowed = [bool]$rbac.Allowed

      $detail = "Scope: $scope`n"
      if (@($req).Count -gt 0) {
        $detail += "Required roles: " + ($req -join ', ') + "`n"
        $detail += "Effective roles: " + (($rbac.Effective | Sort-Object) -join ', ')
        if (-not $rbac.Allowed) {
          $missing = $rbac.Missing -join ', '
          $detail += "`nMissing: $missing"
          $detail += "`nGrant example:`n  az role assignment create --assignee <your-upn-or-objectId> --role `"$missing`" --scope `"$scope`""
        }
      } else {
        $detail += "(No RBAC requirement declared)"
      }

      $menuActions += [pscustomobject]@{
        Label   = $a.Name
        Tag     = [pscustomobject]@{ Action = $a; Scope = $scope; Required = $req }
        Enabled = $isAllowed
        Detail  = $detail
      }
    }

    # --- Action menu with hide/show toggle
    $hideLocked = [bool]$Config.HideLockedActions
    while ($true) {
      $render = if ($hideLocked) { @($menuActions | Where-Object { $_.Enabled }) } else { @($menuActions) }
      if (-not $render) { $render = @() }

      $items = @($render)
      $items += [pscustomobject]@{ Label="(Toggle hide locked: $hideLocked — select to toggle)"; Tag='__toggle__'; Enabled=$true; Detail='Use I for details on a selected item.' }
      $items += [pscustomobject]@{ Label="(Back)"; Tag='__back__'; Enabled=$true; Detail='' }

      $picked = Show-ArrowMenu -Title "Actions for $serviceName  [F=filter, I=details]" -Items $items -ShowLegend
      if (-not $picked) { break }
      if ($picked.Tag -eq '__back__') { break }
      if ($picked.Tag -eq '__toggle__') { $hideLocked = -not $hideLocked; continue }

      # Gate only when roles were declared
      $reqSel = @($picked.Tag.Required)
      if (@($reqSel).Count -gt 0 -and -not $picked.Enabled) {
        Clear-Host
        Write-Host "You lack required roles for this action." -ForegroundColor Yellow
        Write-Host ""
        Write-Host $picked.Detail
        Write-Host ""
        Write-Host "Press any key..."
        [Console]::ReadKey($true) | Out-Null
        continue
      }

      try {
        Write-Host $picked.Tag.Action
        Invoke-Action -Action $picked.Tag.Action
      } catch {
        Write-Host "Action failed: $_" -ForegroundColor Red
        Write-Log "Action failed: $_" 'ERROR'
      }
      Write-Host ""
      Write-Host "Press any key to return to actions..."
      [Console]::ReadKey($true) | Out-Null
    }
  }

} catch {
  Write-Host "Fatal error: $_" -ForegroundColor Red
  Write-Log "Fatal error: $_" 'ERROR'
  exit 1
}
