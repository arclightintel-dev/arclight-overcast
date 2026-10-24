# Runbook: CloudTrail log protection (D-075 / O-015)

The account trail `arclight-staging` writes to the staging-owned bucket
`arclight-staging-trail-20260624130504376400000006` (O-006). Under D-075 the bucket never expires
logs, the trail is multi-region with log file validation, and Object Lock in governance mode keeps
every new log version for 365 days.

## Reading old logs

Log files from before 2026-10-23 that the old 90-day rule expired are **noncurrent versions**
behind a delete marker. `aws s3 ls` does not show them; list them with versions:

```bash
aws s3api list-object-versions --bucket arclight-staging-trail-20260624130504376400000006 \
  --prefix AWSLogs/650880817826/CloudTrail/us-east-1/2026/07/02/ \
  --query 'Versions[?IsLatest==`false`].[Key,VersionId]' --output text
aws s3api get-object --bucket arclight-staging-trail-20260624130504376400000006 \
  --key <key> --version-id <version-id> <local-file>
```

Objects of 128 KB or more move to Glacier Deep Archive after 90 days and need
`aws s3api restore-object` (12-48 hours) before they can be read. Nearly every CloudTrail file
is smaller and stays in Standard.

## Retention on versions that existed before Object Lock (one-time, 2026-10-23)

The bucket's default retention applies only to versions written after Object Lock was enabled.
Older versions, including the 2026-07-02 V-1 restore evidence
(`.../2026/07/02/650880817826_CloudTrail_us-east-1_20260702T2125Z_*`), need an explicit
governance retention. Delete markers cannot be locked and are skipped. Run as an administrator:

```bash
B=arclight-staging-trail-20260624130504376400000006
UNTIL=2027-10-24T00:00:00Z
aws s3api list-object-versions --bucket "$B" \
  --query 'Versions[].[Key,VersionId]' --output text > versions.tsv
# PutObjectRetention per version, 24 at a time; failures go to errors.log
xargs -P 24 -L 1 bash -c 'aws s3api put-object-retention --bucket '"$B"' --key "$0" \
  --version-id "$1" --retention "Mode=GOVERNANCE,RetainUntilDate='"$UNTIL"'" \
  || echo "FAIL $0 $1" >> errors.log' < versions.tsv
```

Verify on a sample, including both V-1 evidence files:

```bash
aws s3api get-object-retention --bucket "$B" --key <key> --version-id <version-id>
```

A retention can be lengthened but, in governance mode, shortened or removed only with
`s3:BypassGovernanceRetention`, which no CI, routine or task role holds.

## Deleting a locked version (exceptional)

Governance mode lets an administrator delete a locked version with
`--bypass-governance-retention`. The bucket policy's `DenyLogDeletion` statement also denies
`s3:DeleteObject` and `s3:DeleteObjectVersion` to every principal, so the policy has to change
first. Both steps are recorded in this repository before they happen. Object Lock itself cannot
be turned off on the bucket.
