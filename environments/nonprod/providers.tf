# Remote state for the nonprod environment. The store is created by
# ../../bootstrap; read ../../bootstrap/README.md before the first init here.

terraform {
  required_version = ">= 1.10"

  backend "azurerm" {
    resource_group_name  = "rg-cronus-tfstate"
    storage_account_name = "cronustfstate001"
    container_name       = "tfstate"
    key                  = "cronus/nonprod.tfstate"
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

    # The Gateway API settings on the cluster have no azurerm argument to live in, so the
    # AKS module writes them as raw ARM properties through AzAPI.
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

# The azuread provider addresses the tenant rather than a subscription, so it takes
# no subscription id. It picks up the same Azure CLI session as the azurerm provider,
# and with it the tenant that session is signed in to.
provider "azuread" {}
