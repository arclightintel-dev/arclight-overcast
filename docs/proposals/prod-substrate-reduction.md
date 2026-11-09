# Prod substrate reduction (DR-19, proposed O-016)

Status: **APPLIED 2026-11-09 (O-016).** Owner direction 2026-11-09: "if it's needlessly costing me money then
let's remove prod" and "go ahead" on this plan. Every apply below needs the owner's go first-hand.

## Why

v1 has no production environment (owner). The prod root (`terraform/envs/prod`, applied 2026-07-02
under D-056/D-058) still runs an RDS instance nobody uses, plus an empty ECS cluster and its
supporting pieces. November's run rate is about $16/day (~$490/month) against a $200 budget; the
prod RDS alone is ~$67/month (Multi-AZ db.t3.small $14.69 + storage $3.26 over Nov 1-8).

The prod **network** is not idle: Backstage (O-012) runs in it. `terraform/envs/backstage/data.tf`
reads the prod VPC, its public and private-app subnets, the ALB and its HTTPS listener, the ALB and
VPC-endpoint security groups, the S3 and interface endpoints, and the SNS topic
`arclight-prod-alarms`. All of those stay.

## Evidence (live reads 2026-11-09)

| Item | Finding |
|---|---|
| ECS `arclight-prod` | ACTIVE, 0 services, 0 tasks |
| RDS `arclight-prod` | available, db.t3.small, Multi-AZ, 50 GB, DeletionProtection **true** (module hardcodes it), backups 7 days |
| Prod roles | `arclight-overcast-terraform-prod`, both prod ECR push roles and both prod service execution roles: **never used**. dbbootstrap and dbverify execution roles: last used 2026-07-03 |
| Prod secrets | values only in the four database URLs and the three dbbootstrap temporaries (all credentials for the database being removed); every other prod shell is empty |
| Prod HTTPS listener | priorities 2 (shuttleforge) and 3 (core) are **hand-made** (DR-11); 4 and 6 are Terraform's; 100 is Backstage's |

## What changes

**Removed (Terraform):**
- `module.rds`: instance, parameter group, subnet group, security group and rules. Terraform takes
  the final snapshot `arclight-prod-final-fcf44ee8` (`skip_final_snapshot = false`). The
  RDS-managed master secret goes with the instance; automated backups are deleted with it (the
  final snapshot is the restore point).
- `module.ecs_cluster` and `aws_ecs_cluster_capacity_providers.this`: the empty cluster and the
  Cloud Map namespace (a private hosted zone, $0.50/month).
- `module.secrets`: 15 secret shells (30-day recovery window), two execution roles and their
  policies, six SSM parameters.
- `module.iam_github_oidc` (prod): the unused Terraform role and two ECR push roles.
- The dbbootstrap and dbverify task definitions, roles, policies, three secret shells and two
  security-group rules.
- The ALB's core and shuttleforge target groups, their listener rules (priorities 4 and 6) and the
  ALB-to-service egress rules: the module gets `services = {}` for prod.
- The three RDS alarms (the observability module gains `create_rds_alarms`, default `true`).

**Kept:** the whole VPC module (VPC, subnets, NAT, IGW, routes, all endpoints, every security
group including the now-ruleless core, shuttleforge and dbbootstrap groups), the ALB with both
listeners, its security group and ingress rules, the SNS topic and its email subscription, the
ALB 5xx alarm (it watches Backstage's ALB), and the prod log groups (bytes only).

**Manual (outside Terraform):** delete the hand-made listener rules at priorities 2 and 3 before
the Terraform removal. They still forward to the target groups Terraform deletes, and ELB refuses
to delete a target group a rule references.

## Module changes

- `modules/rds-postgres`: `deletion_protection` becomes a variable (default `true`; staging is
  unchanged).
- `modules/observability`: `create_rds_alarms` (default `true`).
- No other module changes; prod passes `services = {}` and `service_security_group_ids = {}` to
  `modules/alb`.

## Sequence (each step needs the owner's go)

1. **P0, manual:** delete the listener rules at priorities 2 and 3 **by ARN** (record each rule's
   ARN, conditions and target first: `…/0aabb9a3364a8721` and `…/9ff89e086a39ff68`). Then
   `describe-rules` must show only 4, 6, 100 and the default. Backstage (priority 100) is
   untouched.
2. **P1, apply:** the prod root at commit `a537c0e`, where `module "rds"` sets
   `deletion_protection = false`. The plan is one in-place change on the DB instance plus
   re-creating the alarm-topic email subscription (the July one expired unconfirmed). Apply the
   saved plan, or restore the local `terraform.tfvars` backup first: `a537c0e` still declares
   `github_org` without a default.
3. **P2, apply:** the removal, **re-planned after P1**. Prior state must show
   `deletion_protection = false`. Expected: 71 destroys and nothing else (one add only if the
   subscription lapsed again), nothing in `module.vpc`, the ALB, its listeners or the topic.
   `plan_guard.py` is a formality (no CloudTrail in prod). The DB deletion takes about 10
   minutes; the final snapshot is created first.
4. **P3, verify:**
   - the final snapshot is `available`;
   - the prod plan shows no changes;
   - the **Backstage root plan shows no changes** (its data sources still resolve);
   - Backstage `/ready` is `ready`;
   - the ALB's rules are Backstage's 100 plus the default;
   - the alarm topic shows `SubscriptionsConfirmed = 1`. The owner confirms the AWS email right
     after P1; until then Backstage's alarms reach no one, as they have since the cutover.
5. **P4, record:** DECISIONS O-016, PROJECT_STATE (DR-19 and DR-11 closed), and a note to Complex
   (D-056 production topology is parked, not deleted from the spec).

## Restore

**Database.** The final snapshot restores with `restore-db-instance-from-db-snapshot`; it is
encrypted with the AWS-managed `aws/rds` key, so it restores in this account. A snapshot restore
does not recreate the RDS-managed master secret: run
`modify-db-instance --manage-master-user-password` afterwards. The service-role passwords live only
in the `*/database-url` secrets.

**Everything else.** Reverting this change and re-applying recreates the rest.

**Secrets.** The 18 shells are recoverable for 30 days (`restore-secret`, then import). A rebuild
inside that window fails on the reserved names until they are restored or force-deleted.

## Saving

About **$72/month**:

| Item | Monthly |
|---|---:|
| RDS Multi-AZ db.t3.small | ~$52.60 |
| 50 GB gp3, Multi-AZ | $11.50 |
| 19 secrets (18 shells + the RDS-managed master secret) | $7.60 |
| Cloud Map hosted zone | $0.50 |
| Three alarms | $0.30 |

Secrets marked for deletion are not billed. The final snapshot costs cents.

What remains in the prod network costs about twice that, and Backstage needs it:

| Item | Monthly |
|---|---:|
| 11 endpoint-AZs | ~$80 |
| NAT and its IP | ~$36.50 |
| ALB and its IPs | ~$24 |

A follow-up could pin the three base endpoints (`ecr.api`, `ecr.dkr`, `logs`) to the host's AZ, as
the extra endpoints already are: about $22/month more. It needs a `modules/vpc` change.
