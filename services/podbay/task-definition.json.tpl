[
  {
    "name": "podbay",
    "image": "${image}",
    "essential": true,
    "portMappings": [
      {
        "containerPort": 8099,
        "protocol": "tcp"
      }
    ],
    "healthCheck": {
      "command": ["CMD-SHELL", "curl -f http://localhost:8099/health || exit 1"],
      "interval": 30,
      "timeout": 5,
      "retries": 3,
      "startPeriod": 90
    },
    "environment": [
      { "name": "ENVIRONMENT", "value": "${environment}" },
      { "name": "PODBAY_SUBSTRATE", "value": "ecs" },
      { "name": "PODBAY_ECS_CLUSTER", "value": "${ecs_cluster}" },
      { "name": "PODBAY_ECS_TASK_DEFINITION", "value": "${ecs_task_definition}" },
      { "name": "PODBAY_ECS_CAPACITY_PROVIDER", "value": "${ecs_capacity_provider}" },
      { "name": "PODBAY_ECS_SUBNETS", "value": "${ecs_subnets}" },
      { "name": "PODBAY_ECS_SECURITY_GROUPS", "value": "${ecs_security_groups}" },
      { "name": "PODBAY_EXPORT_S3_BUCKET", "value": "${export_s3_bucket}" },
      { "name": "PODBAY_TURN_ENDPOINT", "value": "${turn_endpoint}" },
      { "name": "PODBAY_TURN_SECRET_NAME", "value": "${turn_secret_name}" },
      { "name": "PODBAY_CORE_JWKS_URL", "value": "${core_jwks_url}" },
      { "name": "PODBAY_CORE_ISSUER", "value": "${core_issuer}" },
      { "name": "PODBAY_EXTERNAL_BASE_URL", "value": "https://podbay.${domain}" },
      { "name": "PODBAY_INSTANCE_MARKER", "value": "podbay-${environment}" },
      { "name": "PODBAY_SNAPSHOT_REGISTRY", "value": "${snapshot_registry}" }
    ],
    "secrets": [
      { "name": "PODBAY_DATABASE_URL", "valueFrom": "${secret_arn_database_url}" }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${log_group}",
        "awslogs-region": "${region}",
        "awslogs-stream-prefix": "podbay"
      }
    }
  }
]
