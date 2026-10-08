# Provider requirement only. The Terraform CLI version is the root module's choice.
#
# Two providers, because identities live on two levels: a managed identity is an
# Azure resource inside a subscription, while a security group is a Microsoft Entra
# directory object in the tenant.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.8, < 6.0"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.10, < 4.0"
    }
  }
}
