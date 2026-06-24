# Runbook: Restore Podbay Workspace

## Context (D-056 §6)

Workspace state lifecycle:
```
Active workspace:     ECS task + attached EBS volume
Workspace seal:       Snapshot EBS volume content to S3 (SEAM-015 export)
Workspace terminate:  EBS volume deleted with task
Workspace recovery:   Launch new task, seed from S3 snapshot
Long-term artifacts:  S3 object storage + metadata in RDS
```

ECS-managed EBS volumes are deleted when the task terminates.
Recovery depends on S3 snapshots created during the seal/export phase.

## Restore from S3 snapshot

### 1. Identify the snapshot

```bash
aws s3 ls s3://arclight-workspace-artifacts/staging/<workspace-id>/
```

### 2. Launch a new workspace task

Use Podbay's API or the ECS RunTask directly:
```bash
# Via Podbay API (preferred)
curl -X POST https://podbay.staging.<domain>/api/workspaces \
  -H "Authorization: Bearer <token>" \
  -d '{"template": "...", "restore_from": "<snapshot-key>"}'
```

### 3. Verify workspace state

Connect to the workspace via the Podbay attach flow and verify
the restored content is correct.

## If no S3 snapshot exists

The workspace data is unrecoverable. EBS volumes are ephemeral
by design — the seal/export step is the only durability mechanism.
This is an accepted tradeoff for v1 (D-056 §6).
