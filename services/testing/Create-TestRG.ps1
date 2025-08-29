<#
.SYNOPSIS
  Creates or updates a resource group — defaults to simulation via -WhatIf.
.DESCRIPTION
  Idempotent: creates RG if missing, otherwise updates tags if provided.
  Uses SupportsShouldProcess, so -WhatIf / -Confirm work as expected.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory = $true)]
  [string]$Location,

  [Parameter(Mandatory = $false)]
  [string]$TagsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure context present
$null = Get-AzContext -ErrorAction Stop

# Parse optional tags
$tags = $null
if ($TagsJson) {
  try {
    $ht = ($TagsJson | ConvertFrom-Json)
    $tags = @{}
    $ht.PSObject.Properties | ForEach-Object { $tags[$_.Name] = [string]$_.Value }
  } catch {
    throw "Invalid TagsJson. Provide JSON like: '{\"env\":\"lab\",\"owner\":\"aviatrix\"}'. $_"
  }
}

$existing = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

if (-not $existing) {
  if ($PSCmdlet.ShouldProcess("RG '$ResourceGroupName' in '$Location'", "Create")) {
    $params = @{
      Name     = $ResourceGroupName
      Location = $Location
      Force    = $true
    }
    if ($tags) { $params['Tag'] = $tags }
    $rg = New-AzResourceGroup @params
    $rg | Select-Object ResourceGroupName, Location, ProvisioningState | Format-Table -AutoSize
  }
} else {
  if ($tags) {
    if ($PSCmdlet.ShouldProcess("RG '$ResourceGroupName'", "Update tags")) {
      Set-AzResourceGroup -Name $ResourceGroupName -Tag $tags -Force |
        Select-Object ResourceGroupName, Location, ProvisioningState |
        Format-Table -AutoSize
    }
  } else {
    Write-Host "Resource group '$ResourceGroupName' already exists. No changes." -ForegroundColor Yellow
  }
}
