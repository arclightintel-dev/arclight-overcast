{
  "family": "arclight-probe-${ENVIRONMENT}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "${EXEC_ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "probe",
      "image": "${IMAGE}",
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/arclight/${ENVIRONMENT}/probe",
          "awslogs-region": "${REGION}",
          "awslogs-stream-prefix": "probe"
        }
      }
    }
  ]
}
