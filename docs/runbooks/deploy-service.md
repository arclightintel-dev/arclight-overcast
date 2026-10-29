# Runbook: Deploy a Service

## Boot order (D-056 §9)

```
1. Core (Tier 0 — no upstream module dependencies)
2. ShuttleForge (depends on Core for JWKS)
3. Nerfherder (depends on Core for JWKS and ShuttleForge for leases; Podbay withdrawn, O-011)
```

Deploy in this order. Each service must pass `/ready` before deploying the next.

## Canonical path: the deploy-service workflow

Service deploys run through `.github/workflows/deploy-service.yml`. The workflow
verifies the image exists in ECR, resolves the tag to its digest and re-registers
the latest task-definition revision with `repo@sha256:<digest>` (O-3; never by tag),
calls `update-service --force-new-deployment`, waits for stability,
and runs a health check against `https://<module>.staging.arclight-complex.net/ready`
**with Cloudflare Access service-token headers** (`CF_ACCESS_CLIENT_ID` /
`CF_ACCESS_CLIENT_SECRET` repo secrets). You do **not** hand-run `update-service`
for a normal deploy.

Prereqs: the module repo's own CI has already built and pushed the image to ECR
as `v1-<git-sha-short>` (Overcast does not build service images — see the
`build-and-push-image.yml` fallback, which only covers `dbbootstrap`).

### Trigger A — manual (workflow_dispatch)

From the GitHub Actions UI (or `gh`), run **Deploy Service** with inputs
`module` (core | shuttleforge), `environment` (staging), and
`image_tag` (e.g. `v1-abc1234`):

```bash
gh workflow run deploy-service.yml \
  -f module=core -f environment=staging -f image_tag=v1-abc1234
```

### Trigger B — cross-repo self-serve (repository_dispatch)

A module repo can trigger its own deploy without opening the Overcast UI. The
workflow listens for `repository_dispatch` of type `deploy-service`:

```bash
echo '{"event_type":"deploy-service","client_payload":{"module":"core","environment":"staging","image_tag":"v1-abc1234"}}' \
  | gh api repos/arclightintel-dev/arclight-overcast/dispatches --input -
```

`client_payload` must carry `module`, `environment`, and `image_tag`. Both
triggers feed the same jobs (`verify-image` → `deploy`).

### Migrations

The workflow does **not** run DB migrations. If a release needs a migration, run
it as a one-off task **before** dispatching the deploy (see manual step 2 below),
or have the service run migrations on boot.

### ShuttleForge specifics

- **Singleton, stop before start** (0/100): every deploy is a short outage, and
  every restart voids all leases.
- **Base revisions are not runnable.** Terraform registers
  `arclight-shuttleforge-staging` and `arclight-shuttleforge-migrate-staging` with an
  all-zero digest. Always deploy through the workflow, or register a copy with the
  real digest. Never point the service at a Terraform revision.
- **Migrations** run in their own family, not as a command override:
  1. Register a copy of the latest `arclight-shuttleforge-migrate-staging` revision with
     the release digest.
  2. Run it with the **dbbootstrap** security group (443 and RDS only, no route to
     Core). It binds only `db-url-migration` and runs `--migrate-only`.
  3. Then re-run `dbbootstrap sf-app-role`, so `alembic_version` stays read-only for the
     runtime role.
  4. Only then deploy.
- **Desired count is 0 until the first deploy.** The workflow cannot start a service
  from zero.
  1. Register the serving revision on the digest.
  2. Run `update-service --task-definition <rev> --desired-count 1`.
  3. Run the workflow's checks by hand: the running digest, and the `/ready` body
     `ready`, since a degraded task also returns 200.
  4. Set `shuttleforge_desired_count = 1` in Terraform before any later apply.
     Otherwise the next apply scales it back to 0.

---

## Break-glass: manual CLI deploy

Use only when the workflow is unavailable. Reproduces what the workflow does.

### 1. Confirm the image exists in ECR

```bash
# Module repo CI pushes the image; Overcast does not build service images.
aws ecr describe-images --repository-name arclight/core --image-ids imageTag=v1-abc1234
```

### 2. Run migration (one-off ECS task, if the release needs one)

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
# Re-register the task definition with the new image tag, then:
aws ecs update-service \
  --cluster arclight-staging \
  --service arclight-core-staging \
  --task-definition arclight-core-staging:<new-revision> \
  --force-new-deployment
```

### 4. Verify deployment

Staging is fronted by a **Cloudflare Access gate** — a bare curl returns `302`.
Pass the service-token headers (token lives in
`C:\Users\jkcos\.arclight\cf_access_service_token.env`):

```bash
source /c/Users/jkcos/.arclight/cf_access_service_token.env  # CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET

aws ecs wait services-stable --cluster arclight-staging --services arclight-core-staging

CF=(-H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET")

# Readiness via ALB (through Cloudflare)
curl -f "${CF[@]}" https://core.staging.arclight-complex.net/ready

# Build identity: the running task's image digest, from ECS (not /ready/detail, which
# requires a human, MFA-gated admin from Core S-049 on)
aws ecs describe-tasks --cluster arclight-staging \
  --tasks $(aws ecs list-tasks --cluster arclight-staging --service-name arclight-core-staging \
            --desired-status RUNNING --query 'taskArns' --output text) \
  --query 'tasks[].[taskDefinitionArn,containers[0].imageDigest]' --output text
aws ecr describe-images --repository-name arclight/core --image-ids imageTag=<tag> \
  --query 'imageDetails[0].imageDigest' --output text
```

Expected: `/ready` returns 200 with `"status": "ready"`, and every running task is on the new
revision with the tag's digest (or, for a multi-arch index, its linux/amd64 child). The
`deploy-service.yml` workflow checks both.

### 5. Populate secrets (first deployment only)

Secrets Manager shells are created by Terraform. Populate values out-of-band.
Secret names are lowercase-hyphen (authoritative list:
`terraform/modules/secrets/main.tf`) — note `database-url`, **not** `DATABASE_URL`:

```bash
aws secretsmanager put-secret-value \
  --secret-id arclight/staging/core/database-url \
  --secret-string 'postgresql+asyncpg://core_staging:PASSWORD@<rds-endpoint>:5432/core_staging'
```

Repeat for each secret. Bootstrap of the DB roles + `database-url` values is
handled by `bootstrap-databases.md` (Step 6).

## Rollback

```bash
# Roll back to previous task definition revision
aws ecs update-service \
  --cluster arclight-staging \
  --service arclight-core-staging \
  --task-definition arclight-core-staging:<previous-revision> \
  --force-new-deployment
```

Verify the rollback the same way as a deploy: `/ready` 200 with `"status": "ready"`, and the
running tasks on `<previous-revision>` with its image digest. Do not use `/ready/detail`.
