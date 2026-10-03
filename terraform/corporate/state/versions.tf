terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100.0"
    }
  }

  backend "s3" {
    bucket              = "arclight-corporate-terraform-state-650880817826"
    key                 = "state/terraform.tfstate"
    region              = "us-east-1"
    encrypt             = true
    use_lockfile        = true
    allowed_account_ids = ["650880817826"]
  }
}
