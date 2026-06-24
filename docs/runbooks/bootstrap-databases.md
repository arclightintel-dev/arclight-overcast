# Runbook: Bootstrap Databases (Phase 0C)

Creates per-service databases and roles on the RDS instance via a Fargate one-off task.

## Prerequisites

- `terraform apply` completed (Phase 0B)
- SNS email subscription confirmed
- Cloudflare CNAMEs created
- `arclight/dbbootstrap` ECR repository exists

## Step 1: Build and push bootstrap image

```bash
cd services/dbbootstrap/
docker build -t arclight/dbbootstrap:v1 .

aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin 650880817826.dkr.ecr.us-east-1.amazonaws.com

docker tag arclight/dbbootstrap:v1 \
  650880817826.dkr.ecr.us-east-1.amazonaws.com/arclight/dbbootstrap:v1
docker push 650880817826.dkr.ecr.us-east-1.amazonaws.com/arclight/dbbootstrap:v1
```

## Step 2: Populate temporary bootstrap password secrets

```bash
CORE_PW=$(openssl rand -hex 24)
SF_PW=$(openssl rand -hex 24)
PODBAY_PW=$(openssl rand -hex 24)
NF_PW=$(openssl rand -hex 24)

# Write to a protected local file — needed for DATABASE_URL construction in Step 5
umask 077
cat > /tmp/arclight-phase0-db.env <<EOF
CORE_PW=$CORE_PW
SF_PW=$SF_PW
PODBAY_PW=$PODBAY_PW
NF_PW=$NF_PW
EOF
echo "Passwords saved to /tmp/arclight-phase0-db.env (mode 600)"

aws secretsmanager put-secret-value \
  --secret-id arclight/staging/dbbootstrap/core-db-password \
  --secret-string "$CORE_PW"
aws secretsmanager put-secret-value \
  --secret-id arclight/staging/dbbootstrap/shuttleforge-db-password \
  --secret-string "$SF_PW"
aws secretsmanager put-secret-value \
  --secret-id arclight/staging/dbbootstrap/podbay-db-password \
  --secret-string "$PODBAY_PW"
aws secretsmanager put-secret-value \
  --secret-id arclight/staging/dbbootstrap/nerfherder-db-password \
  --secret-string "$NF_PW"
```

## Step 3: Preflight checks

Verify image and secrets exist before running the task:

```bash
aws ecr describe-images --repository-name arclight/dbbootstrap --image-ids imageTag=v1

for secret in core-db-password shuttleforge-db-password podbay-db-password nerfherder-db-password; do
  aws secretsmanager get-secret-value \
    --secret-id "arclight/staging/dbbootstrap/$secret" \
    --query 'Name' --output text || { echo "FAIL: $secret has no value"; exit 1; }
done
echo "Preflight passed."
```

## Step 4: Run bootstrap task

```bash
cd terraform/envs/staging/
BOOTSTRAP_SG=$(terraform output -raw sg_dbbootstrap_id)
SUBNETS=$(terraform output -json private_app_subnet_ids)

TASK_ARN=$(aws ecs run-task \
  --cluster arclight-staging \
  --task-definition arclight-dbbootstrap-staging \
  --launch-type FARGATE \
  --platform-version "1.4.0" \
  --network-configuration "{
    \"awsvpcConfiguration\": {
      \"subnets\": $SUBNETS,
      \"securityGroups\": [\"$BOOTSTRAP_SG\"],
      \"assignPublicIp\": \"DISABLED\"
    }
  }" \
  --query 'tasks[0].taskArn' --output text)

echo "Task: $TASK_ARN"
aws ecs wait tasks-stopped --cluster arclight-staging --tasks "$TASK_ARN"

EXIT_CODE=$(aws ecs describe-tasks --cluster arclight-staging --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' --output text)
echo "Exit code: $EXIT_CODE"

if [ "$EXIT_CODE" != "0" ]; then
  echo "BOOTSTRAP FAILED — diagnosing:"
  aws ecs describe-tasks \
    --cluster arclight-staging \
    --tasks "$TASK_ARN" \
    --query 'tasks[0].{lastStatus:lastStatus,stopCode:stopCode,stoppedReason:stoppedReason,containers:containers[*].{name:name,exitCode:exitCode,reason:reason}}'
  aws logs tail /arclight/staging/dbbootstrap --since 30m
  exit 1
fi
```

Common failures: secret has no value (task fails before entrypoint runs), SG blocks
egress to RDS or HTTPS endpoints, ECR image tag mismatch, execution role missing
permissions.

## Step 5: Verify master bootstrap (GATE)

```bash
VERIFY_ARN=$(aws ecs run-task \
  --cluster arclight-staging \
  --task-definition arclight-dbbootstrap-staging \
  --launch-type FARGATE \
  --platform-version "1.4.0" \
  --network-configuration "{
    \"awsvpcConfiguration\": {
      \"subnets\": $SUBNETS,
      \"securityGroups\": [\"$BOOTSTRAP_SG\"],
      \"assignPublicIp\": \"DISABLED\"
    }
  }" \
  --overrides '{
    "containerOverrides": [{
      "name": "dbbootstrap",
      "command": ["verify"]
    }]
  }' \
  --query 'tasks[0].taskArn' --output text)

echo "Verify task: $VERIFY_ARN"
aws ecs wait tasks-stopped --cluster arclight-staging --tasks "$VERIFY_ARN"

EXIT_CODE=$(aws ecs describe-tasks --cluster arclight-staging --tasks "$VERIFY_ARN" \
  --query 'tasks[0].containers[0].exitCode' --output text)
echo "Verify exit code: $EXIT_CODE"

if [ "$EXIT_CODE" != "0" ]; then
  echo "MASTER VERIFY FAILED:"
  aws logs tail /arclight/staging/dbbootstrap --since 15m
  exit 1
fi
```

Expected: databases and roles exist, CREATE/DROP TABLE succeeds in each database.

## Step 6: Populate DATABASE_URL secrets

Reload passwords from the protected file, then construct connection strings:

```bash
source /tmp/arclight-phase0-db.env
RDS_HOST=$(terraform output -raw rds_endpoint | cut -d: -f1)

aws secretsmanager put-secret-value \
  --secret-id arclight/staging/core/database-url \
  --secret-string "postgresql://core_staging:${CORE_PW}@${RDS_HOST}:5432/core_staging"

aws secretsmanager put-secret-value \
  --secret-id arclight/staging/shuttleforge/db-url \
  --secret-string "postgresql://shuttleforge_staging:${SF_PW}@${RDS_HOST}:5432/shuttleforge_staging"

aws secretsmanager put-secret-value \
  --secret-id arclight/staging/podbay/database-url \
  --secret-string "postgresql://podbay_staging:${PODBAY_PW}@${RDS_HOST}:5432/podbay_staging"

aws secretsmanager put-secret-value \
  --secret-id arclight/staging/nerfherder/database-url \
  --secret-string "postgresql://nerfherder_staging:${NF_PW}@${RDS_HOST}:5432/nerfherder_staging"
```

## Step 7: Verify service-role access (GATE)

```bash
SVC_VERIFY_ARN=$(aws ecs run-task \
  --cluster arclight-staging \
  --task-definition arclight-dbverify-svc-staging \
  --launch-type FARGATE \
  --platform-version "1.4.0" \
  --network-configuration "{
    \"awsvpcConfiguration\": {
      \"subnets\": $SUBNETS,
      \"securityGroups\": [\"$BOOTSTRAP_SG\"],
      \"assignPublicIp\": \"DISABLED\"
    }
  }" \
  --overrides '{
    "containerOverrides": [{
      "name": "dbbootstrap",
      "command": ["verify-service"]
    }]
  }' \
  --query 'tasks[0].taskArn' --output text)

echo "Service verify task: $SVC_VERIFY_ARN"
aws ecs wait tasks-stopped --cluster arclight-staging --tasks "$SVC_VERIFY_ARN"

EXIT_CODE=$(aws ecs describe-tasks --cluster arclight-staging --tasks "$SVC_VERIFY_ARN" \
  --query 'tasks[0].containers[0].exitCode' --output text)
echo "Service verify exit code: $EXIT_CODE"

if [ "$EXIT_CODE" != "0" ]; then
  echo "SERVICE VERIFY FAILED:"
  aws logs tail /arclight/staging/dbbootstrap --since 15m
  exit 1
fi
```

Expected: each service role connects and can CREATE/DROP TABLE.

## Step 8: Cleanup

Mark bootstrap secrets spent and delete the local password file:

```bash
for secret in core-db-password shuttleforge-db-password podbay-db-password nerfherder-db-password; do
  aws secretsmanager put-secret-value \
    --secret-id "arclight/staging/dbbootstrap/$secret" \
    --secret-string "BOOTSTRAP_COMPLETE"
done

rm -f /tmp/arclight-phase0-db.env
echo "Phase 0C complete."
```
