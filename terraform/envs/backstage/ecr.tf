# Backstage's three repositories. Account-level ECR repositories otherwise live in staging
# state (O-006); these are owned here because nothing else uses them (recorded in O-012).
# Immutable tags; the lifecycle keeps the thirty newest v-prefixed tags per repository
# (app v1-<sha>, Portal v3-<sha>, Litestream mirror v1-0.3.13). Raised from the module's ten
# (owner, 2026-11-10): every push to Backstage's main builds an image, and rollback needs the
# target release's exact digests still in ECR, across the move to a new repository.
module "ecr" {
  source = "../../modules/ecr"

  environment            = var.environment
  max_tagged_image_count = 30
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
