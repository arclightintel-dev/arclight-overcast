[
  {
    "name": "workspace-browser",
    "image": "${image}",
    "essential": true,
    "cpu": 1024,
    "memory": 2048,
    "memoryReservation": 1536,
    "portMappings": [
      { "containerPort": 9222, "protocol": "tcp" },
      { "containerPort": 9280, "protocol": "tcp" },
      { "containerPort": 8080, "protocol": "tcp" }
    ],
    "linuxParameters": {
      "initProcessEnabled": true,
      "sharedMemorySize": 256,
      "capabilities": {
        "add": ["SYS_ADMIN"]
      }
    },
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${log_group}",
        "awslogs-region": "${region}",
        "awslogs-stream-prefix": "workspace"
      }
    }
  }
]
