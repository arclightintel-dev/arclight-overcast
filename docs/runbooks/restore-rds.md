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
  --db-subnet-group-name arclight-staging-db \
  --no-publicly-accessible
```

### 3. Verify data

Connect to the restored instance and verify the data is correct.

### 4. Swap endpoints

Option A: Update Secrets Manager DATABASE_URL entries to point to the new instance.
Option B: Rename the original instance, then rename the restored instance to the original name.

### 5. Restart services

Force new deployment on all services to pick up the new endpoint:

```bash
for svc in arclight-core-staging arclight-shuttleforge-staging arclight-podbay-staging; do
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
