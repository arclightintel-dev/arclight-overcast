{
  "family": "arclight-shuttleforge-${environment}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "${cpu}",
  "memory": "${memory}",
  "executionRoleArn": "${execution_role_arn}",
  "taskRoleArn": "${task_role_arn}",
  "containerDefinitions": [
    {
      "name": "shuttleforge",
      "image": "${image}",
      "essential": true,
      "portMappings": [
        { "containerPort": 9000, "protocol": "tcp" },
        { "containerPort": 9050, "protocol": "tcp" },
        { "containerPort": 9100, "protocol": "tcp" }
      ],
      "ulimits": [
        { "name": "nofile", "softLimit": 65536, "hardLimit": 65536 }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:9000/ready || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      },
      "environment": [
        { "name": "ENVIRONMENT", "value": "${environment}" },
        { "name": "CORE_JWKS_URL", "value": "http://core.${environment}.arclight.local:8000/.well-known/jwks.json" },
        { "name": "CORE_INTERNAL_URL", "value": "http://core.${environment}.arclight.local:8000" }
      ],
      "secrets": [
        { "name": "SHUTTLEFORGE_DB_URL", "valueFrom": "${secret_arn_db_url}" },
        { "name": "SHUTTLEFORGE_KEK_RING_B64", "valueFrom": "${secret_arn_kek_ring}" },
        { "name": "SHUTTLEFORGE_LISTENER_AUTH_HMAC_KEY", "valueFrom": "${secret_arn_listener_hmac}" },
        { "name": "SHUTTLEFORGE_LEASE_HMAC_KEY", "valueFrom": "${secret_arn_lease_hmac}" },
        { "name": "SHUTTLEFORGE_OPERATOR_TOKEN", "valueFrom": "${secret_arn_operator_token}" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${log_group}",
          "awslogs-region": "${region}",
          "awslogs-stream-prefix": "shuttleforge"
        }
      }
    }
  ]
}
