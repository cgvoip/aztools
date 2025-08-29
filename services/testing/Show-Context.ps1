<#
.SYNOPSIS
  Prints the current Az context (tenant, subscription, account).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ctx = Get-AzContext
if (-not $ctx) { throw "No Az context. Run Connect-AzAccount first." }

$acct = $ctx.Account
$sub  = $ctx.Subscription
$ten  = $ctx.Tenant

$info = [pscustomobject]@{
  TimeUTC          = (Get-Date).ToUniversalTime()
  TenantId         = $ten.Id
  SubscriptionId   = $sub.Id
  SubscriptionName = $sub.Name
  AccountId        = $acct.Id
  AccountType      = $acct.Type
  Environment      = $ctx.Environment.Name
}

$info | Format-List
