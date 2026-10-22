# Backstage's three repositories. Account-level ECR repositories otherwise live in staging
# state (O-006); these are owned here because nothing else uses them (recorded in O-012).
# Immutable tags; the lifecycle keeps the ten newest v-prefixed tags per repository
# (app v1-<sha>, Portal v3-<sha>, Litestream mirror v1-0.3.13).
module "ecr" {
  source = "../../modules/ecr"

  environment = var.environment
  repository_names = [
    "arclight/backstage",
    "arclight/backstage-portal",
    "arclight/litestream",
  ]
}

locals {
  ecr_repository_arns = values(module.ecr.repository_arns)
  ecr_registry        = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}
