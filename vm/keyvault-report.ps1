# Connect to Azure
Connect-AzAccount

# Output file path
$OutputFile = "C:\Temp\KeyVaultInventoryReport.csv"

# Initialize results array
$Results = @()

# Get all subscriptions
$Subscriptions = Get-AzSubscription

foreach ($Sub in $Subscriptions) {

    Write-Host "Processing subscription: $($Sub.Name)" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $Sub.Id | Out-Null

    $Vaults = Get-AzKeyVault

    foreach ($Vault in $Vaults) {

        Write-Host "  Scanning vault: $($Vault.VaultName)" -ForegroundColor Yellow

        # Get Keys
        $Keys = Get-AzKeyVaultKey -VaultName $Vault.VaultName -ErrorAction SilentlyContinue
        foreach ($Key in $Keys) {
            $Results += [PSCustomObject]@{
                SubscriptionName = $Sub.Name
                SubscriptionId   = $Sub.Id
                ResourceGroup    = $Vault.ResourceGroupName
                VaultName        = $Vault.VaultName
                ObjectType       = "Key"
                Name             = $Key.Name
                Enabled          = $Key.Attributes.Enabled
                Created          = $Key.Attributes.Created
                Expires          = $Key.Attributes.Expires
                Updated          = $Key.Attributes.Updated
            }
        }

        # Get Secrets
        $Secrets = Get-AzKeyVaultSecret -VaultName $Vault.VaultName -ErrorAction SilentlyContinue
        foreach ($Secret in $Secrets) {
            $Results += [PSCustomObject]@{
                SubscriptionName = $Sub.Name
                SubscriptionId   = $Sub.Id
                ResourceGroup    = $Vault.ResourceGroupName
                VaultName        = $Vault.VaultName
                ObjectType       = "Secret"
                Name             = $Secret.Name
                Enabled          = $Secret.Attributes.Enabled
                Created          = $Secret.Attributes.Created
                Expires          = $Secret.Attributes.Expires
                Updated          = $Secret.Attributes.Updated
            }
        }

        # Get Certificates
        $Certs = Get-AzKeyVaultCertificate -VaultName $Vault.VaultName -ErrorAction SilentlyContinue
        foreach ($Cert in $Certs) {
            $Results += [PSCustomObject]@{
                SubscriptionName = $Sub.Name
                SubscriptionId   = $Sub.Id
                ResourceGroup    = $Vault.ResourceGroupName
                VaultName        = $Vault.VaultName
                ObjectType       = "Certificate"
                Name             = $Cert.Name
                Enabled          = $Cert.Attributes.Enabled
                Created          = $Cert.Attributes.Created
                Expires          = $Cert.Attributes.Expires
                Updated          = $Cert.Attributes.Updated
            }
        }
    }
}

# Display structured table in console
$Results | Sort-Object SubscriptionName, VaultName, ObjectType |
    Format-Table -AutoSize

# Export to CSV
$Results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

Write-Host "`nReport exported to: $OutputFile" -ForegroundColor Green
