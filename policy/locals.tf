locals {
  policy_name        = "DeployAzureHybridBenefitWindows"
  policy_display_name = "Deploy Azure Hybrid Benefit for Windows"
  policy_description  = "This policy ensures virtual machines are configured for Azure Hybrid Benefit for eligible Windows VMs (Windows Server/Client). Reference: https://learn.microsoft.com/azure/virtual-machines/windows/hybrid-use-benefit-licensing"
  policy_category     = "Compute"
}