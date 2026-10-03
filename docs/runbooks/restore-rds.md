# Runbook: Restore RDS from Snapshot

## When to use

- Data corruption or accidental deletion
- Failed migration that can't be rolled back
- Point-in-time recovery needed

## Steps

### 1. Identify the snapshot

```bash
# List automated snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier arclight-staging \
  --snapshot-type automated \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table
```

### 2. Restore to a new instance

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier arclight-staging-restored \
  --db-snapshot-identifier <snapshot-id> \
  --db-instance-class db.t3.micro \
  --db-subnet-group-name arclight-staging \
  --no-publicly-accessible
```

> **Subnet group name is `arclight-staging`** (verified live and in
> `terraform/modules/rds-postgres`), not `arclight-staging-db`.
>
> **Managed master password:** the source instance uses
> `manage_master_user_password = true` (master user `arclight_admin`, secret
> `rds!db-...`). A snapshot restore does **not** re-enable a managed secret on the
> restored instance — add `--manage-master-user-password` if you need one, or set
> a master password explicitly. Application connectivity uses the per-service
> `.../database-url` secrets (service roles), not the master secret.

### 3. Verify data

Connect to the restored instance and verify the data is correct.

### 4. Swap endpoints

Option A: Update the per-service `.../database-url` secrets to point at the new
instance. Note the connection strings embed the RDS host, so the host segment
must be rewritten (secret names are lowercase-hyphen —
`arclight/staging/core/database-url`, `.../shuttleforge/db-url`,
`.../podbay/database-url`, `.../nerfherder/database-url`; see
`terraform/modules/secrets/main.tf`).
Option B: Rename the original instance, then rename the restored instance to the
original name (endpoint host stays the same — no secret edits needed).

### 5. Restart services

Force new deployment on the deployed services to pick up the new endpoint. Only
**core** and **podbay** are currently deployed as ECS services (verified via
`ecs list-services`); ShuttleForge is not yet running — add it to the loop once
it is:

```bash
for svc in arclight-core-staging arclight-podbay-staging; do
  aws ecs update-service --cluster arclight-staging --service $svc --force-new-deployment
done
```

### 6. Cleanup

Delete the old instance once verified:
```bash
aws rds delete-db-instance \
  --db-instance-identifier arclight-staging-old \
  --skip-final-snapshot
```
