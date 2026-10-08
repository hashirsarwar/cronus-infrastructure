terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
  }

  # The first apply writes state locally, because the storage account that will
  # hold it does not exist yet. Once that apply has succeeded, uncomment the
  # block below and run `terraform init -migrate-state` to hand the state over
  # to the account this configuration just created. See README.md.
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-cronus-tfstate"
  #   storage_account_name = "cronustfstate001"
  #   container_name       = "tfstate"
  #   key                  = "cronus/bootstrap.tfstate"
  #   use_azuread_auth     = true
  #   use_cli              = true
  # }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}
