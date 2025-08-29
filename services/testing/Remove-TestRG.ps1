<#
.SYNOPSIS
  Deletes a resource group (simulated by default via -WhatIf).

.DESCRIPTION
  Uses SupportsShouldProcess so -WhatIf / -Confirm work.
  Requires appropriate RBAC at the RG scope (your menu gates this to Owner for testing).
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure we have an Azure context
$null = Get-AzContext -ErrorAction Stop

# Check existence
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
  Write-Host "Resource group '$ResourceGroupName' not found." -ForegroundColor Yellow
  return
}

# Perform delete (respecting -WhatIf / -Confirm)
if ($PSCmdlet.ShouldProcess("Resource group '$ResourceGroupName'", "Delete")) {
  Remove-AzResourceGroup -Name $ResourceGroupName -Force -ErrorAction Stop
  Write-Host "Delete initiated for '$ResourceGroupName'." -ForegroundColor Green
}
