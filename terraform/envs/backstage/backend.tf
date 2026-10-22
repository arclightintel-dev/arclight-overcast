terraform {
  backend "s3" {
    bucket       = "arclight-terraform-state"
    key          = "backstage/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
