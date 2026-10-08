# Provider requirement only. The Terraform CLI version is the root module's choice.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.8, < 6.0"
    }

    # The Gateway API settings have no azurerm argument to live in, so they are written as
    # raw ARM properties instead.
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.13, < 3.0"
    }
  }
}
