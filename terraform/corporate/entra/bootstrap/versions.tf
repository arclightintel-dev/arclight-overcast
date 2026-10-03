terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10.0"
    }
  }

  backend "s3" {}
}
