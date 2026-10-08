# Remote state for the prod environment. The store is created by
# ../../bootstrap; read ../../bootstrap/README.md before the first init here.

terraform {
  required_version = ">= 1.10"

  backend "azurerm" {
    resource_group_name  = "rg-cronus-tfstate"
    storage_account_name = "cronustfstate001"
    container_name       = "tfstate"
    key                  = "cronus/prod.tfstate"
    use_azuread_auth     = true
    use_cli              = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }

    # AzAPI manages Gateway API properties that azurerm cannot express; Gateways themselves live in GitOps.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}

# Pin AzAPI to the same subscription as azurerm instead of inheriting the CLI's selected subscription.
provider "azapi" {
  subscription_id = var.subscription_id
}

# The directory is tenant-wide: environment separation comes from identity names and grants.
# The provider uses the CLI tenant and takes no subscription ID.
provider "azuread" {}
