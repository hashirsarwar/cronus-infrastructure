# Provider requirement only. The Terraform CLI version is the root module's choice.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.8, < 6.0"
    }
  }
}
