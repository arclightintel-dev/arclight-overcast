{
  "family": "arclight-podbay-${environment}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["EC2"],
  "cpu": "${cpu}",
  "memory": "${memory}",
  "executionRoleArn": "${execution_role_arn}",
  "taskRoleArn": "${task_role_arn}",
  "containerDefinitions": [
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
        "command": ["CMD-SHELL", "curl -f http://localhost:8099/ready || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 90
      },
      "environment": [
        { "name": "ENVIRONMENT", "value": "${environment}" },
        { "name": "CORE_JWKS_URL", "value": "http://core.${environment}.arclight.local:8000/.well-known/jwks.json" },
        { "name": "CORE_BASE_URL", "value": "https://core.${domain}" },
        { "name": "PODBAY_PUBLIC_URL", "value": "https://podbay.${domain}" },
        { "name": "SHUTTLEFORGE_INTERNAL_URL", "value": "http://shuttleforge.${environment}.arclight.local:9000" }
      ],
      "secrets": [
        { "name": "DATABASE_URL", "valueFrom": "${secret_arn_database_url}" }
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
}
