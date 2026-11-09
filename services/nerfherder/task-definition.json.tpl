[
  {
    "name": "nerfherder",
    "image": "${image}",
    "essential": true,
    "portMappings": [
      { "containerPort": 8100, "protocol": "tcp" }
    ],
    "stopTimeout": 35,
    "healthCheck": {
      "command": ["CMD", "python", "-c", "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://localhost:8100/ready', timeout=2).status == 200 else 1)"],
      "interval": 10,
      "timeout": 5,
      "retries": 6,
      "startPeriod": 20
    },
    "environment": [
      { "name": "ENVIRONMENT", "value": "${environment}" },
      { "name": "NERFHERDER_DATABASE_SSL_MODE", "value": "require" },
      { "name": "NERFHERDER_DATABASE_POOL_SIZE", "value": "5" },
      { "name": "NERFHERDER_DATABASE_MAX_OVERFLOW", "value": "5" },
      { "name": "CORE_URL", "value": "http://core.${namespace}:8000" },
      { "name": "NERFHERDER_JWKS_URL", "value": "http://core.${namespace}:8000/.well-known/jwks.json" },
      { "name": "NERFHERDER_ALLOW_PLAINTEXT_INTERNAL_HTTP", "value": "true" },
      { "name": "NERFHERDER_CORE_CLIENT_ID", "value": "${core_client_id}" },
      { "name": "SHUTTLEFORGE_URL", "value": "http://shuttleforge.${namespace}:9000" },
      { "name": "NERFHERDER_S3_BUCKET", "value": "${bucket}" },
      { "name": "NERFHERDER_S3_REGION", "value": "${region}" },
      { "name": "NERFHERDER_S3_ENDPOINT_URL", "value": "" },
      { "name": "NERFHERDER_S3_ACCESS_KEY", "value": "" },
      { "name": "NERFHERDER_S3_SECRET_KEY", "value": "" },
      { "name": "NERFHERDER_EVENT_SINK_MODE", "value": "disabled" },
      { "name": "NERFHERDER_EGRESS_MODE", "value": "sf_required" }
    ],
    "secrets": [
      { "name": "NERFHERDER_DATABASE_URL", "valueFrom": "${secret_arn_database_url}" },
      { "name": "NERFHERDER_CORE_CLIENT_SECRET", "valueFrom": "${secret_arn_core_client_secret}" }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${log_group}",
        "awslogs-region": "${region}",
        "awslogs-stream-prefix": "nerfherder"
      }
    }
  }
]
