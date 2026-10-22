# Runbook: Restore RDS from Snapshot

## When to use

- Data corruption or accidental deletion
- Failed migration that can't be rolled back
- Point-in-time recovery needed

## Steps

### 0. Take a manual snapshot before a risky change

```bash
aws rds create-db-snapshot \
  --db-instance-identifier arclight-staging \
  --db-snapshot-identifier arclight-staging-pre-<change>-<yyyymmdd>
aws rds wait db-snapshot-available \
  --db-snapshot-identifier arclight-staging-pre-<change>-<yyyymmdd>
```

For a schema migration, take it after the consuming service is scaled to zero so the
snapshot carries no in-flight writes. As of 2026-10-22 one manual snapshot exists:
`arclight-staging-pre-core-p7-20261021` (Core P7 pre-migration, 2026-10-21T21:04Z, not shared).
Otherwise only the 7-day automated backups do. This runbook has never been executed (R3).

### 1. Identify the snapshot

```bash
# List automated snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier arclight-staging \
  --snapshot-type automated \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table

# List manual snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier arclight-staging \
  --snapshot-type manual \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table
```

### 2. Restore to a new instance

```bash
# Security group of the current instance. The restored instance does NOT inherit it;
# without this flag it lands in the VPC default security group and no service can connect.
RDS_SG=$(aws rds describe-db-instances --db-instance-identifier arclight-staging \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier arclight-staging-restored \
  --db-snapshot-identifier <snapshot-id> \
  --db-instance-class db.t3.micro \
  --db-subnet-group-name arclight-staging \
  --vpc-security-group-ids "$RDS_SG" \
  --no-publicly-accessible \
  --deletion-protection

aws rds wait db-instance-available --db-instance-identifier arclight-staging-restored
```

> **Found 2026-10-21 (Core deploy-plan review)**: earlier versions of this runbook omitted
> `--vpc-security-group-ids`. A restore run that way is unreachable from ECS until the
> security group is corrected with `modify-db-instance --vpc-security-group-ids`.
>
> **Subnet group name is `arclight-staging`** (verified live and in
> `terraform/modules/rds-postgres`), not `arclight-staging-db`.
>
> **Managed master password:** the source instance uses
> `manage_master_user_password = true` (master user `arclight_admin`, secret
> `rds!db-...`). A snapshot restore does **not** re-enable a managed secret on the
> restored instance — add `--manage-master-user-password` if you need one, or set
> a master password explicitly. Application connectivity uses the per-service
> `.../database-url` secrets (service roles), not the master secret.

Point-in-time restore is the alternative when no manual snapshot exists (automated
backups, 7-day window):

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier arclight-staging \
  --target-db-instance-identifier arclight-staging-restored \
  --restore-time <UTC timestamp> \
  --db-instance-class db.t3.micro \
  --db-subnet-group-name arclight-staging \
  --vpc-security-group-ids "$RDS_SG" \
  --no-publicly-accessible \
  --deletion-protection
```

Expect a 20 GB `db.t3.micro` to reach `available` in 10–20 minutes.

### 3. Verify data

Connect to the restored instance and verify the data is correct (for a schema rollback,
`select version_num from alembic_version` must show the pre-migration head).

### 4. Swap endpoints

**Default: Option B (rename).** The per-service connection strings embed the RDS host,
so keeping the endpoint name avoids editing four secrets and redeploying every consumer
with a changed value.

Option B: Rename the original instance, then rename the restored instance to the
original name (endpoint host stays the same — no secret edits needed). Deletion
protection on the original must be disabled before it can be renamed away or deleted.

```bash
aws rds modify-db-instance --db-instance-identifier arclight-staging \
  --new-db-instance-identifier arclight-staging-old --apply-immediately
aws rds wait db-instance-available --db-instance-identifier arclight-staging-old
aws rds modify-db-instance --db-instance-identifier arclight-staging-restored \
  --new-db-instance-identifier arclight-staging --apply-immediately
aws rds wait db-instance-available --db-instance-identifier arclight-staging
```

Option A: Update the per-service `.../database-url` secrets to point at the new
instance. Note the connection strings embed the RDS host, so the host segment
must be rewritten (secret names are lowercase-hyphen —
`arclight/staging/core/database-url`, `.../shuttleforge/db-url`,
`.../podbay/database-url`, `.../nerfherder/database-url`; see
`terraform/modules/secrets/main.tf`).

### 5. Restart services

Force new deployment on the deployed services to pick up the new endpoint. Only
**core** is running as an ECS service (Podbay was stopped on 2026-10-21, O-011;
ShuttleForge and Nerfherder are not yet deployed — add them to the loop once they
are). If a service was scaled to zero for the change, set the desired count and
the intended task-definition revision explicitly instead of relying on
`--force-new-deployment` alone:

```bash
for svc in arclight-core-staging; do
  aws ecs update-service --cluster arclight-staging --service $svc --force-new-deployment
done
# or, for a service parked at zero during a migration rollback:
aws ecs update-service --cluster arclight-staging --service arclight-core-staging \
  --task-definition arclight-core-staging:<previous revision> --desired-count 1
```

### 6. Cleanup

Delete the old instance once verified (disable deletion protection first):

```bash
aws rds modify-db-instance --db-instance-identifier arclight-staging-old \
  --no-deletion-protection --apply-immediately
aws rds delete-db-instance \
  --db-instance-identifier arclight-staging-old \
  --skip-final-snapshot
```

Terraform note: after a rename-based restore the instance Terraform manages still has the
identifier `arclight-staging`, but attributes such as the resource ID and ARN change. Run
`terraform plan` from `terraform/envs/staging` before the next apply and import or
reconcile as needed; do not apply blind.
