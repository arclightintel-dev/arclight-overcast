"""Fail a Terraform plan that would weaken CloudTrail log protection (D-075 / O-015).

Usage: terraform show -json <plan file> > plan.json && python scripts/plan_guard.py plan.json

Terraform's prevent_destroy cannot catch this: a branch cut before the protection landed has
no block for it at all, so the plan simply removes it. This reads the planned changes instead
and exits 1 if any of them would:
  - delete or replace the trail bucket, its Object Lock configuration, its bucket policy or the
    trail;
  - give the trail bucket's lifecycle an expiration (current or noncurrent);
  - drop the bucket policy's DenyLogDeletion statement;
  - turn off the trail's multi-region logging or log file validation.

It prints resource addresses and reasons only, never attribute values (the repository is
public). Run it in CI (terraform-plan.yml) and before every staging apply (DEVELOPMENT.md).
"""
import json
import sys

PROTECTED = {
    ("aws_s3_bucket", "cloudtrail"),
    ("aws_s3_bucket_object_lock_configuration", "cloudtrail"),
    ("aws_s3_bucket_policy", "cloudtrail"),
    ("aws_cloudtrail", "this"),
}


def violations(plan):
    out = []
    for rc in plan.get("resource_changes", []):
        key = (rc.get("type"), rc.get("name"))
        actions = rc.get("change", {}).get("actions", [])
        after = rc.get("change", {}).get("after") or {}
        addr = rc.get("address", "?")
        if key in PROTECTED and "delete" in actions:
            out.append(f"{addr}: planned {'/'.join(actions)}")
        if key == ("aws_s3_bucket_lifecycle_configuration", "cloudtrail") and "delete" not in actions:
            for rule in after.get("rule") or []:
                if rule.get("expiration") or rule.get("noncurrent_version_expiration"):
                    out.append(f"{addr}: lifecycle rule {rule.get('id', '?')!r} would expire logs")
        if key == ("aws_s3_bucket_policy", "cloudtrail") and "delete" not in actions and after.get("policy"):
            sids = [s.get("Sid") for s in json.loads(after["policy"]).get("Statement", [])]
            if "DenyLogDeletion" not in sids:
                out.append(f"{addr}: bucket policy would drop DenyLogDeletion")
        if key == ("aws_cloudtrail", "this") and "delete" not in actions and after:
            if after.get("is_multi_region_trail") is False:
                out.append(f"{addr}: trail would stop being multi-region")
            if after.get("enable_log_file_validation") is False:
                out.append(f"{addr}: trail would turn off log file validation")
    return out


def main():
    with open(sys.argv[1], encoding="utf-8") as fh:
        plan = json.load(fh)
    found = violations(plan)
    if found:
        print("plan_guard: FAIL - this plan weakens CloudTrail log protection (D-075 / O-015):")
        for line in found:
            print("  " + line)
        print("If this is intended, it needs a new decision first; otherwise rebase onto main.")
        sys.exit(1)
    print("plan_guard: OK (CloudTrail log protection unchanged)")


if __name__ == "__main__":
    main()
