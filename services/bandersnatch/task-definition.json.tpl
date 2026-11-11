[
  {
    "name": "bandersnatch",
    "image": "${image}",
    "essential": true,
    "portMappings": [
      { "containerPort": 8080, "protocol": "tcp" },
      { "containerPort": 8081, "protocol": "tcp" }
    ],
    "stopTimeout": 90,
    "readonlyRootFilesystem": true,
    "mountPoints": [
      { "sourceVolume": "tmp", "containerPath": "/tmp", "readOnly": false }
    ],
    "healthCheck": {
      "command": ["CMD", "python", "-c", "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://localhost:8081/ready', timeout=2).status == 200 else 1)"],
      "interval": 10,
      "timeout": 5,
      "retries": 6,
      "startPeriod": 60
    },
    "environment": [
      { "name": "BSN_ENV", "value": "${environment}" },
      { "name": "AWS_REGION", "value": "${region}" },
      { "name": "BSN_PUBLIC_HOST", "value": ${jsonencode(public_host)} },
      { "name": "BSN_TABLE_PREFIX", "value": "${table_prefix}" },
      { "name": "BSN_BUCKET", "value": "${bucket}" },
      { "name": "BSN_MAIL_MODE", "value": "${mail_mode}" },
      { "name": "BSN_MAIL_FROM", "value": ${jsonencode(mail_from)} },
      { "name": "BSN_MAIL_FROM_NAME", "value": ${jsonencode(mail_from_name)} },
      { "name": "BSN_MAIL_REPLY_TO", "value": ${jsonencode(mail_reply_to)} },
      { "name": "BSN_MAIL_SUBJECT", "value": ${jsonencode(mail_subject)} },
      { "name": "BSN_GRAPH_TENANT_ID", "value": ${jsonencode(graph_tenant_id)} },
      { "name": "BSN_GRAPH_CLIENT_ID", "value": ${jsonencode(graph_client_id)} },
      { "name": "BSN_PAGE_TITLE", "value": ${jsonencode(page_title)} }
    ],
    "secrets": [
      { "name": "BSN_ORIGIN_SECRET", "valueFrom": "${secret_arn_origin_secret}" },
      { "name": "BSN_GRAPH_CLIENT_SECRET", "valueFrom": "${secret_arn_graph_client_secret}" }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${log_group}",
        "awslogs-region": "${region}",
        "awslogs-stream-prefix": "bandersnatch"
      }
    }
  }
]
