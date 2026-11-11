################################################################################
# Bandersnatch: a gated delivery page (spec docs/proposals/bandersnatch.md, sections 6.2 and 9).
#
# One Fargate task behind the staging ALB, DynamoDB tables, a read-only payload bucket and two
# secret shells. Everything here is behind var.bandersnatch_enabled; only the ECR repository
# and the push role (modules ecr and iam-github-oidc) exist without it. The public hostname,
# mail addresses and wording are sensitive variables and appear in no address, name or tag.
# Service at desired count 0 by default: applying this starts nothing.
################################################################################

locals {
  bsn_name    = "bandersnatch"
  bsn_enabled = var.bandersnatch_enabled
  bsn_count   = var.bandersnatch_enabled ? 1 : 0

  bsn_table_prefix = "arclight-bandersnatch-${var.environment}-"
  bsn_bucket       = "arclight-${var.environment}-bandersnatch-payload"
  bsn_log_group    = "/arclight/${var.environment}/bandersnatch"

  # Until a real digest is given, the base revision names a digest that cannot exist (as for
  # Nerfherder): a stray scale-up fails to pull instead of running something unintended.
  bsn_image_unset = "${module.ecr.repository_urls["arclight/bandersnatch"]}@sha256:${format("%064d", 0)}"
  bsn_image       = var.bandersnatch_image != "" ? var.bandersnatch_image : local.bsn_image_unset

  # String keys throughout. task_actions is everything the task role may do on the table; the
  # operator tool (administrator credentials) is the only writer of the rest.
  bsn_tables = {
    accounts = { hash_key = "account_id", range_key = "item", gsi_key = null, ttl = false, task_actions = [] }
    releases = { hash_key = "release_id", range_key = null, gsi_key = null, ttl = false, task_actions = ["dynamodb:GetItem", "dynamodb:Scan"] }
    tokens   = { hash_key = "token_hash", range_key = null, gsi_key = "account_id", ttl = false, task_actions = ["dynamodb:GetItem", "dynamodb:UpdateItem"] }
    links    = { hash_key = "nonce_hash", range_key = null, gsi_key = null, ttl = true, task_actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"] }
    sessions = { hash_key = "session_hash", range_key = null, gsi_key = null, ttl = true, task_actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"] }
    limits   = { hash_key = "key", range_key = null, gsi_key = null, ttl = true, task_actions = ["dynamodb:UpdateItem"] }
    audit    = { hash_key = "event_id", range_key = null, gsi_key = "account_id", ttl = true, task_actions = ["dynamodb:PutItem"] }
  }
}

################################################################################
# DynamoDB tables
################################################################################

resource "aws_dynamodb_table" "bandersnatch" {
  for_each = local.bsn_enabled ? local.bsn_tables : {}

  name                        = "${local.bsn_table_prefix}${each.key}"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = each.value.hash_key
  range_key                   = each.value.range_key
  deletion_protection_enabled = true

  dynamic "attribute" {
    for_each = toset(compact([each.value.hash_key, each.value.range_key, each.value.gsi_key]))
    content {
      name = attribute.value
      type = "S"
    }
  }

  dynamic "global_secondary_index" {
    for_each = each.value.gsi_key != null ? [each.value.gsi_key] : []
    content {
      name            = "by-account"
      hash_key        = global_secondary_index.value
      projection_type = "ALL"
    }
  }

  dynamic "ttl" {
    for_each = each.value.ttl ? [1] : []
    content {
      attribute_name = "ttl"
      enabled        = true
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "${local.bsn_table_prefix}${each.key}" }
}

################################################################################
# Payload bucket: written only by the operator tool, never deleted from, no lifecycle rule
################################################################################

resource "aws_s3_bucket" "bandersnatch" {
  count = local.bsn_count

  bucket = local.bsn_bucket

  tags = { Name = local.bsn_bucket }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "bandersnatch" {
  count = local.bsn_count

  bucket                  = aws_s3_bucket.bandersnatch[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "bandersnatch" {
  count = local.bsn_count

  bucket = aws_s3_bucket.bandersnatch[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bandersnatch" {
  count = local.bsn_count

  bucket = aws_s3_bucket.bandersnatch[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "bandersnatch" {
  count = local.bsn_count

  bucket = aws_s3_bucket.bandersnatch[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "bandersnatch" {
  count = local.bsn_count

  bucket = aws_s3_bucket.bandersnatch[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "TLSOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.bandersnatch[0].arn, "${aws_s3_bucket.bandersnatch[0].arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        # Nobody deletes a payload object or one of its versions, administrators included.
        Sid       = "NoDeletes"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
        Resource  = ["${aws_s3_bucket.bandersnatch[0].arn}/*"]
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.bandersnatch]
}

################################################################################
# Secrets (shells only, INV-004) and logs
################################################################################

resource "aws_secretsmanager_secret" "bsn_origin_secret" {
  count = local.bsn_count

  name        = "arclight/${var.environment}/bandersnatch/origin-secret"
  description = "Bandersnatch origin secret: the X-Origin-Auth value the edge adds to every request"

  tags = { Name = "arclight/${var.environment}/bandersnatch/origin-secret" }
}

resource "aws_secretsmanager_secret" "bsn_graph_client_secret" {
  count = local.bsn_count

  name        = "arclight/${var.environment}/bandersnatch/graph-client-secret"
  description = "Bandersnatch Entra client secret for Microsoft Graph sendMail (graph mail mode)"

  tags = { Name = "arclight/${var.environment}/bandersnatch/graph-client-secret" }
}

resource "aws_cloudwatch_log_group" "bandersnatch" {
  count = local.bsn_count

  name              = local.bsn_log_group
  retention_in_days = 365

  tags = { Name = local.bsn_log_group }
}

################################################################################
# Roles. The names fall outside the CI deploy role's PassRole patterns on purpose
# (iam-github-oidc): CI cannot run a task as this service.
################################################################################

resource "aws_iam_role" "bsn_exec" {
  count = local.bsn_count

  name               = "arclight-bandersnatch-exec-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = { Name = "arclight-bandersnatch-exec-${var.environment}" }
}

resource "aws_iam_role" "bsn_task" {
  count = local.bsn_count

  name               = "arclight-bandersnatch-task-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = { Name = "arclight-bandersnatch-task-${var.environment}" }
}

resource "aws_iam_role_policy" "bsn_exec" {
  count = local.bsn_count

  name = "runtime-exec"
  role = aws_iam_role.bsn_exec[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RuntimeSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.bsn_origin_secret[0].arn, aws_secretsmanager_secret.bsn_graph_client_secret[0].arn]
      },
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
        ]
        Resource = [module.ecr.repository_arns["arclight/bandersnatch"]]
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.bandersnatch[0].arn}:*"]
      },
    ]
  })
}

# Per table, exactly the interface's list: the task reads tokens and releases and writes its own
# links, sessions, counters and audit events. Nothing on accounts, no index access, no deletes.
resource "aws_iam_role_policy" "bsn_task_tables" {
  count = local.bsn_count

  name = "tables"
  role = aws_iam_role.bsn_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for name, t in local.bsn_tables : {
        Sid      = title(name)
        Effect   = "Allow"
        Action   = t.task_actions
        Resource = [aws_dynamodb_table.bandersnatch[name].arn]
      } if length(t.task_actions) > 0
    ]
  })
}

resource "aws_iam_role_policy" "bsn_task_payload" {
  count = local.bsn_count

  name = "payload-read"
  role = aws_iam_role.bsn_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadReleases"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.bandersnatch[0].arn}/releases/*"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "bsn_task_ses" {
  count = local.bsn_enabled && var.bandersnatch_mail_mode == "ses" ? 1 : 0

  name = "ses-send"
  role = aws_iam_role.bsn_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SendMail"
        Effect   = "Allow"
        Action   = ["ses:SendEmail"]
        Resource = ["*"]
      },
    ]
  })
}

################################################################################
# Network: the service's group and every path it uses. No rule to RDS, Core, ShuttleForge or
# Nerfherder.
################################################################################

resource "aws_security_group" "bandersnatch" {
  count = local.bsn_count

  name_prefix = "arclight-${var.environment}-bandersnatch-"
  description = "Bandersnatch Fargate tasks"
  vpc_id      = module.vpc.vpc_id

  tags = { Name = "sg-bandersnatch-${var.environment}" }
}

# 8080 carries traffic; 8081 serves only /ready, which no listener forwards to.
resource "aws_security_group_rule" "bsn_from_alb" {
  for_each = local.bsn_enabled ? toset(["8080", "8081"]) : toset([])

  type                     = "ingress"
  from_port                = tonumber(each.key)
  to_port                  = tonumber(each.key)
  protocol                 = "tcp"
  security_group_id        = aws_security_group.bandersnatch[0].id
  source_security_group_id = module.alb.alb_security_group_id
  description              = "Staging ALB to Bandersnatch ${each.key}"
}

# Standalone rules on the ALB's group (it has no inline rules), as for the Backstage host.
resource "aws_security_group_rule" "alb_to_bsn" {
  for_each = local.bsn_enabled ? toset(["8080", "8081"]) : toset([])

  type                     = "egress"
  from_port                = tonumber(each.key)
  to_port                  = tonumber(each.key)
  protocol                 = "tcp"
  security_group_id        = module.alb.alb_security_group_id
  source_security_group_id = aws_security_group.bandersnatch[0].id
  description              = "Staging ALB to Bandersnatch ${each.key}"
}

resource "aws_security_group_rule" "bsn_to_vpce_443" {
  count = local.bsn_count

  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.bandersnatch[0].id
  source_security_group_id = module.vpc.sg_vpc_endpoints_id
  description              = "Bandersnatch to interface endpoints (secrets, ECR, logs)"
}

resource "aws_security_group_rule" "bsn_to_s3_443" {
  count = local.bsn_count

  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.bandersnatch[0].id
  prefix_list_ids   = [module.vpc.s3_prefix_list_id]
  description       = "Bandersnatch to S3 through the gateway endpoint (payload, image layers)"
}

resource "aws_security_group_rule" "bsn_to_dynamodb_443" {
  count = local.bsn_count

  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.bandersnatch[0].id
  prefix_list_ids   = [module.vpc.dynamodb_prefix_list_id]
  description       = "Bandersnatch to DynamoDB through the gateway endpoint"
}

# EXCEPTION to O-017 (no internet egress for consumer services), graph mail mode only: mail is
# sent over HTTPS to login.microsoftonline.com and graph.microsoft.com, which have no stable
# address range to name. The rule disappears when the mail mode is ses or log.
resource "aws_security_group_rule" "bsn_to_internet_443_graph" {
  count = local.bsn_enabled && var.bandersnatch_mail_mode == "graph" ? 1 : 0

  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.bandersnatch[0].id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Bandersnatch to Microsoft Graph and Entra (O-017 exception, graph mail mode)"
}

################################################################################
# ALB: the first-level wildcard certificate on the staging listener (SNI), an own target group
# and one host rule. Health checks go to 8081, so /ready is not public.
################################################################################

data "aws_acm_certificate" "wildcard" {
  count = local.bsn_count

  domain      = "*.${var.domain_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}

resource "aws_lb_listener_certificate" "bandersnatch" {
  count = local.bsn_count

  listener_arn    = module.alb.https_listener_arn
  certificate_arn = data.aws_acm_certificate.wildcard[0].arn
}

resource "aws_lb_target_group" "bandersnatch" {
  count = local.bsn_count

  name                 = "arclight-${var.environment}-bandersnatch"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = module.vpc.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/ready"
    port                = "8081"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = { Name = "arclight-${var.environment}-bandersnatch" }
}

resource "aws_lb_listener_rule" "bandersnatch" {
  count = local.bsn_count

  listener_arn = module.alb.https_listener_arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bandersnatch[0].arn
  }

  condition {
    host_header {
      values = [var.bandersnatch_public_host]
    }
  }

  lifecycle {
    precondition {
      condition     = var.bandersnatch_public_host != ""
      error_message = "bandersnatch_public_host must be set in terraform.tfvars when bandersnatch_enabled is true."
    }
  }
}

################################################################################
# Service: no internet egress from the module (the graph exception is its own rule above), no
# database path, no ECS Exec (O-018 posture: the module never enables it).
################################################################################

module "bandersnatch_service" {
  count  = local.bsn_count
  source = "../../modules/ecs-service-fargate"

  service_name           = local.bsn_name
  environment            = var.environment
  cluster_id             = module.ecs_cluster.cluster_id
  cluster_name           = module.ecs_cluster.cluster_name
  subnet_ids             = module.vpc.private_app_subnet_ids
  security_group_id      = aws_security_group.bandersnatch[0].id
  alb_security_group_id  = module.alb.alb_security_group_id
  cloud_map_namespace_id = module.ecs_cluster.cloud_map_namespace_id
  container_port         = 8080
  internet_egress        = false
  desired_count          = var.bandersnatch_desired_count
  cpu                    = 256
  memory                 = 512
  execution_role_arn     = aws_iam_role.bsn_exec[0].arn
  task_role_arn          = aws_iam_role.bsn_task[0].arn

  # The root's own target group, passed through the listener rule so the service attaches only
  # once the group has a load balancer. Not target_group_arn: the module decides a count from
  # it, which needs a value known at plan time, and would add its own 8080 ingress rule.
  additional_load_balancers = [{
    target_group_arn = aws_lb_listener_rule.bandersnatch[0].action[0].target_group_arn
    container_port   = 8080
  }]

  # Read-only root file system: /tmp is a Fargate ephemeral volume (Fargate has no tmpfs).
  ephemeral_volumes = ["tmp"]

  container_definitions = templatefile("${path.module}/../../../services/bandersnatch/task-definition.json.tpl", {
    environment                    = var.environment
    image                          = local.bsn_image
    region                         = var.aws_region
    log_group                      = local.bsn_log_group
    table_prefix                   = local.bsn_table_prefix
    bucket                         = local.bsn_bucket
    public_host                    = var.bandersnatch_public_host
    mail_mode                      = var.bandersnatch_mail_mode
    mail_from                      = var.bandersnatch_mail_from
    mail_from_name                 = var.bandersnatch_mail_from_name
    mail_reply_to                  = var.bandersnatch_mail_reply_to
    mail_subject                   = var.bandersnatch_mail_subject
    graph_tenant_id                = var.bandersnatch_graph_tenant_id
    graph_client_id                = var.bandersnatch_graph_client_id
    page_title                     = var.bandersnatch_page_title
    secret_arn_origin_secret       = aws_secretsmanager_secret.bsn_origin_secret[0].arn
    secret_arn_graph_client_secret = aws_secretsmanager_secret.bsn_graph_client_secret[0].arn
  })
}
