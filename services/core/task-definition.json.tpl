{
  "family": "arclight-core-${environment}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "${cpu}",
  "memory": "${memory}",
  "executionRoleArn": "${execution_role_arn}",
  "taskRoleArn": "${task_role_arn}",
  "containerDefinitions": [
    {
      "name": "core",
      "image": "${image}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8000,
          "protocol": "tcp"
        }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8000/ready || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      },
      "environment": [
        { "name": "ENVIRONMENT", "value": "${environment}" },
        { "name": "CORE_ISSUER", "value": "https://core.internal" },
        { "name": "CORE_BASE_URL", "value": "https://core.${domain}" }
      ],
      "secrets": [
        { "name": "CORE_DATABASE_URL", "valueFrom": "${secret_arn_database_url}" },
        { "name": "CORE_SIGNING_KEY_ENCRYPTION_KEY", "valueFrom": "${secret_arn_signing_key}" },
        { "name": "CORE_ADMIN_BOOTSTRAP_SECRET", "valueFrom": "${secret_arn_admin_bootstrap}" },
        { "name": "OIDC_GOOGLE_CLIENT_SECRET", "valueFrom": "${secret_arn_oidc_google}" },
        { "name": "OIDC_MICROSOFT_CLIENT_SECRET", "valueFrom": "${secret_arn_oidc_microsoft}" },
        { "name": "OIDC_GITHUB_CLIENT_SECRET", "valueFrom": "${secret_arn_oidc_github}" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${log_group}",
          "awslogs-region": "${region}",
          "awslogs-stream-prefix": "core"
        }
      }
    }
  ]
}
