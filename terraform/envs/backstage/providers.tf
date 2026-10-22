# Backstage (O-012): a prototype platform application on one EC2 Docker host in the prod VPC,
# behind the prod ALB. This root owns only Backstage's resources; the VPC, the ALB, its
# listener and the interface endpoints belong to terraform/envs/prod and are read here
# through data sources. The two resources this root attaches to prod objects (a listener
# rule and an ALB security-group egress rule) are standalone, so neither root reconciles
# the other's away.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "arclight"
      ManagedBy   = "terraform"
      App         = "backstage"
    }
  }
}
