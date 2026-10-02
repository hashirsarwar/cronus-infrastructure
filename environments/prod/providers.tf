terraform {
  required_version = ">= 1.10"

  backend "azurerm" {
    resource_group_name  = "rg-cronus-tfstate"
    storage_account_name = "cronustfstate001"
    container_name       = "tfstate"
    key                  = "cronus/prod.tfstate"
    use_azuread_auth     = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}
