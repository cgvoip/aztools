<#
.SYNOPSIS
  Lists resource groups in the active subscription.
.PARAMETER NameLike
  Optional wildcard to filter RG names (e.g., '*aviatrix*').
#>
# [CmdletBinding()]
# param(
#   [string]$NameLike
# )

$NameLike = "NetworkWatcherRG"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$null = Get-AzContext -ErrorAction Stop  # ensure logged in/context set

$rgs = @(Get-AzResourceGroup -ErrorAction Stop)
if ($NameLike) {
  $rgs = @($rgs | Where-Object { $_.ResourceGroupName -like $NameLike })
}

if ($rgs.Count -eq 0) {
  Write-Host "No resource groups found." -ForegroundColor Yellow
  return
}

$rgs |
  Select-Object ResourceGroupName, Location, ProvisioningState |
  Sort-Object ResourceGroupName |
  Format-Table -AutoSize
