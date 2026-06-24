# Runbook: Deploy a Service

## Boot order (D-056 §9)

```
1. Core (Tier 0 — no upstream module dependencies)
2. ShuttleForge (depends on Core for JWKS)
3. Podbay (depends on Core for JWKS, ShuttleForge for leases at Phase 3)
```

Deploy in this order. Each service must pass `/ready` before deploying the next.

## Steps

### 1. Build and push image (in module repo)

```bash
# In the module repo (e.g., arclight-core)
docker build -t arclight/core:$(git rev-parse --short HEAD) .
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
docker tag arclight/core:$(git rev-parse --short HEAD) <account-id>.dkr.ecr.us-east-1.amazonaws.com/arclight/core:$(git rev-parse --short HEAD)
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/arclight/core:$(git rev-parse --short HEAD)
```

### 2. Run migration (one-off ECS task)

```bash
aws ecs run-task \
  --cluster arclight-staging \
  --task-definition arclight-core-staging \
  --launch-type FARGATE \
  --network-configuration '{...}' \
  --overrides '{"containerOverrides": [{"name": "core", "command": ["alembic", "upgrade", "head"]}]}'
```

Wait for the task to complete (exit code 0) before proceeding.

### 3. Update service with new image

```bash
# Update task definition with new image tag, then:
aws ecs update-service \
  --cluster arclight-staging \
  --service arclight-core-staging \
  --task-definition arclight-core-staging:<new-revision> \
  --force-new-deployment
```

### 4. Verify deployment

```bash
# Wait for rolling update to complete
aws ecs wait services-stable --cluster arclight-staging --services arclight-core-staging

# Check readiness via ALB
curl -f https://core.staging.<domain>/ready

# Check detailed readiness
curl -s https://core.staging.<domain>/ready/detail | jq .
```

Expected: `{"module": "core", "status": "ready", ...}`

### 5. Populate secrets (first deployment only)

Secrets Manager shells were created by Terraform. Populate values:

```bash
aws secretsmanager put-secret-value \
  --secret-id arclight/staging/core/DATABASE_URL \
  --secret-string 'postgresql+asyncpg://core_staging:PASSWORD@rds-endpoint:5432/core_staging'
```

Repeat for each secret. See terraform/modules/secrets/ for the full list.

## Rollback

```bash
# Roll back to previous task definition revision
aws ecs update-service \
  --cluster arclight-staging \
  --service arclight-core-staging \
  --task-definition arclight-core-staging:<previous-revision> \
  --force-new-deployment
```
