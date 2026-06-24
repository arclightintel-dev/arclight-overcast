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

# SAVE THESE VALUES — needed for DATABASE_URL construction in Step 5
echo "core=$CORE_PW sf=$SF_PW podbay=$PODBAY_PW nf=$NF_PW"
```

## Step 3: Run bootstrap task

```bash
cd terraform/envs/staging/
BOOTSTRAP_SG=$(terraform output -raw sg_dbbootstrap_id)

TASK_ARN=$(aws ecs run-task \
  --cluster arclight-staging \
  --task-definition arclight-dbbootstrap-staging \
  --launch-type FARGATE \
  --platform-version "1.4.0" \
  --network-configuration "{
    \"awsvpcConfiguration\": {
      \"subnets\": $(terraform output -json private_app_subnet_ids),
      \"securityGroups\": [\"$BOOTSTRAP_SG\"],
      \"assignPublicIp\": \"DISABLED\"
    }
  }" \
  --query 'tasks[0].taskArn' --output text)

echo "Task: $TASK_ARN"
aws ecs wait tasks-stopped --cluster arclight-staging --tasks "$TASK_ARN"
aws ecs describe-tasks --cluster arclight-staging --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode'
```

Expected exit code: 0. Check `/arclight/staging/dbbootstrap` logs if non-zero.

## Step 4: Verify (master credentials)

```bash
aws ecs run-task \
  --cluster arclight-staging \
  --task-definition arclight-dbbootstrap-staging \
  --launch-type FARGATE \
  --platform-version "1.4.0" \
  --network-configuration "{
    \"awsvpcConfiguration\": {
      \"subnets\": $(terraform output -json private_app_subnet_ids),
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
  --query 'tasks[0].taskArn' --output text
```

Check logs: databases and roles should exist, CREATE/DROP TABLE succeeds in each database.

## Step 5: Populate DATABASE_URL secrets

Using the passwords saved from Step 2 and the RDS endpoint:

```bash
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

## Step 6: Verify service-role access

```bash
aws ecs run-task \
  --cluster arclight-staging \
  --task-definition arclight-dbverify-svc-staging \
  --launch-type FARGATE \
  --platform-version "1.4.0" \
  --network-configuration "{
    \"awsvpcConfiguration\": {
      \"subnets\": $(terraform output -json private_app_subnet_ids),
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
  --query 'tasks[0].taskArn' --output text
```

Check logs: each service role connects and can CREATE/DROP TABLE.

## Step 7: Mark bootstrap secrets spent

```bash
for secret in core-db-password shuttleforge-db-password podbay-db-password nerfherder-db-password; do
  aws secretsmanager put-secret-value \
    --secret-id "arclight/staging/dbbootstrap/$secret" \
    --secret-string "BOOTSTRAP_COMPLETE"
done
```
