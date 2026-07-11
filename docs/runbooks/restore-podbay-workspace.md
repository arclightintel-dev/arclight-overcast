# Runbook: Restore Podbay Workspace

> **STATUS — needs owner review.** This runbook previously described an
> "ECS-managed EBS volume + EBS-snapshot-to-S3" lifecycle. That does not match
> the deployed substrate (verified against `terraform/envs/staging/main.tf`,
> `services/podbay/workspace-task-definition.json.tpl`, and the live task def).
> The infra facts below are corrected and grounded; the **seal / export / restore
> API semantics are owned by the Podbay module** (a separate repo) and are marked
> FLAG — confirm them with the Podbay owner before relying on this procedure.

## Deployed substrate (grounded)

- Workspace task def: `arclight-podbay-workspace-staging` — **launch type `EC2`**,
  `awsvpc` networking (live rev 14, image `arclight/podbay-workspace-browser:v1-fix2`).
- Runs on the **EC2 capacity provider** (`module.ec2_capacity`) in the dedicated
  **private workspace subnets** (`10.0.30.0/24`, `10.0.31.0/24` —
  `module.vpc.private_workspace_subnet_ids`), SG `sg_podbay_workspace_id`.
- **No EBS volume is attached** by the task definition. There is no EBS snapshot
  lifecycle. Durable workspace state is exported to **S3**, not to EBS snapshots.
- Export bucket: `arclight-podbay-exports-staging-<suffix>` (created with
  `bucket_prefix`; live name
  `arclight-podbay-exports-staging-20260708090259166400000002`). The controller
  receives it as `PODBAY_EXPORT_S3_BUCKET`. There is **no**
  `arclight-workspace-artifacts` bucket — that name in the old runbook was wrong.
- Workspaces are launched/stopped by the **Podbay controller** service
  (`arclight-podbay-staging`, Fargate) via `ecs:RunTask` against the workspace
  task def + capacity provider (env in `services/podbay/task-definition.json.tpl`:
  `PODBAY_ECS_*`). Overcast provisions the substrate; the controller drives
  workspace lifecycle.

## Restore from S3 export

### 1. Identify the export

```bash
# Resolve the export bucket from Terraform output (do not hardcode the suffix)
cd terraform/envs/staging
BUCKET=$(C:/Tools/terraform.exe output -raw podbay_export_bucket_name)

aws s3 ls "s3://$BUCKET/podbay-exports/" --recursive | grep <workspace-id>
```

Exports live under the `podbay-exports/` prefix (30-day lifecycle expiry per
`aws_s3_bucket_lifecycle_configuration.podbay_exports`).

### 2. Launch a restored workspace (via the Podbay controller)  — FLAG

Workspaces are created through the Podbay controller API, not by hand-running
`ecs run-task`. Staging is behind the **Cloudflare Access gate**, so a bare curl
returns `302` — pass the service-token headers (token in
`C:\Users\jkcos\.arclight\cf_access_service_token.env`):

```bash
source /c/Users/jkcos/.arclight/cf_access_service_token.env
curl -X POST https://podbay.staging.arclight-complex.net/api/workspaces \
  -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
  -H "Authorization: Bearer <token>" \
  -d '{"template": "...", "restore_from": "<export-key>"}'
```

> **FLAG:** the exact endpoint path, request body (`restore_from` vs other field
> names), and whether restore is exposed via API at all are **Podbay-owned** and
> unverified from Overcast code. Confirm against the Podbay module before use.

### 3. Verify workspace state

Attach to the workspace through the Podbay attach flow and confirm the restored
content is correct.

## If no S3 export exists

Workspace data is unrecoverable. The EC2 workspace task has no persistent volume;
the S3 export (SEAM-015) is the only durability mechanism. Accepted v1 tradeoff
(D-056 §6).
