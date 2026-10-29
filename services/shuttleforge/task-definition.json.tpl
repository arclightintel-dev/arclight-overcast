[
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
    "stopTimeout": 30,
    "healthCheck": {
      "command": ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9000/ready', timeout=3)"],
      "interval": 30,
      "timeout": 5,
      "retries": 3,
      "startPeriod": 120
    },
    "environment": [
      { "name": "SHUTTLEFORGE_BIND", "value": "0.0.0.0" },
      { "name": "SHUTTLEFORGE_ALLOW_CONTROL_PUBLIC", "value": "true" },
      { "name": "SHUTTLEFORGE_API_PORT", "value": "9000" },
      { "name": "SHUTTLEFORGE_PROXY_PORT", "value": "9050" },
      { "name": "SHUTTLEFORGE_MITM_PORT", "value": "9100" },
      { "name": "SHUTTLEFORGE_TRANSPORT_ENDPOINT", "value": "http://shuttleforge.${namespace}:9050" },
      { "name": "SHUTTLEFORGE_CORE_JWKS_URL", "value": "http://core.${namespace}:8000/.well-known/jwks.json" },
      { "name": "SHUTTLEFORGE_REQUIRE_PG", "value": "true" },
      { "name": "SHUTTLEFORGE_DB_EXPECTED_NAME", "value": "shuttleforge_${environment}" },
      { "name": "SHUTTLEFORGE_DB_TLS_MODE", "value": "require" },
      { "name": "SHUTTLEFORGE_SKIP_MIGRATIONS", "value": "true" },
      { "name": "SHUTTLEFORGE_PROVIDER_BOOT_TIMEOUT_SECONDS", "value": "30" },
      { "name": "SHUTTLEFORGE_POLICY_FILE", "value": "/data/policy.yaml" },
      { "name": "SHUTTLEFORGE_LEASE_AUTH_ENABLED", "value": "true" },
      { "name": "SHUTTLEFORGE_DATAPLANE_AUTH_ENABLED", "value": "true" },
      { "name": "SHUTTLEFORGE_SNAPSHOT_DEBOUNCE_SECONDS", "value": "1" },
      { "name": "SHUTTLEFORGE_PROVIDER_VALIDATION_INTERVAL_SECONDS", "value": "900" },
      { "name": "SHUTTLEFORGE_PROVIDER_VALIDATION_COOLDOWN_SECONDS", "value": "300" }
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
