# Overcast response — Nerfherder P3.5 onboarding questions

> **Answered**: 2026-10-20 | **To**: Nerfherder claude-main session (owner-authorized direct ping) | **Overcast baseline**: `main` at `b492a2f`
> **Source question set**: `arclight-nerfherder@abca15a:docs/plans/p35_questions_for_overcast.md` (read-only)
> **Scope**: answers only. No apply, deploy, secret value or configuration change. Nothing here lifts the charter / D-056 §15 deferral of Nerfherder deployment.

NF's own inventory of Overcast ("what we believe we found") was correct on every point.

| # | Question | Answer | Overcast evidence |
|---|---|---|---|
| 1 | Environment | Staging under D-059 §9. No NF-only environment exists or is planned. Prod is substrate-only, out of P3.5 scope. | D-059 pos. 5; `terraform/envs/prod/main.tf` (no services) |
| 2 | Sequencing / who applies | Owner's call. Owner priority (2026-09-30) is Entra + Cloudflare, then deployment-model rework. Overcast can prepare the wiring PR anytime; the apply is owner-run locally as `john-admin` (DR-1). | `docs/PROJECT_STATE.md` debt register DR-1 |
| 3 | ShuttleForge in the VPC | Not wired, not deployed, 0 images. "Blocked on PostgreSQL" is stale (SF.9 closed 2026-09-30). Current blockers: SF manifest defects M-1..M-6, Overcast O-1..O-4, no staging restore drill (R3), SF.11 deferred. Before-or-with NF: owner sequencing. | [SF manifest receipt](shuttleforge-deployment-manifest-response.md) |
| 4 | Rollout shape | Not today: module hardcodes 100/200 and no template sets `stopTimeout`. Fix is O-2 (module variables; SF and NF get 0/100, `desired_count` 1). `stopTimeout` of 35 s or more is a container-definition field NF's template can set (Fargate max 120). Successor mechanism: stop-then-start. | `terraform/modules/ecs-service-fargate/main.tf:95–96` |
| 5 | Egress | NF→Core:8000 and NF→SF (9000/9050/9100) rules: yes, existing pattern; a new NF security group is required. Port 80 egress already absent. **Denying 443 is not possible today**: interface endpoints exist for `ecr.api`, `ecr.dkr`, `logs` plus an S3 gateway, none for Secrets Manager/KMS/SSM, so secret injection transits NAT on 443. Fail-closed requires adding those endpoints (roadmap Phase 6; NF's requirement is the justification) and then scoping NF's 443 egress to the endpoint SG and the SF SG. | `terraform/modules/vpc/main.tf:167–203`; `terraform/modules/ecs-service-fargate/main.tf:56–64`; `terraform/envs/staging/main.tf:790–809` |
| 6 | Core | Internal base `http://core.staging.internal.arclight-complex.net:8000`; issuer `https://core.internal` (D-056); plain HTTP, no private CA. `prn_svc_nerfherder` registration is Core data: unknown to Overcast. | `terraform/envs/staging/main.tf:96, 919` |
| 7 | Secrets / identity | Only `arclight/staging/nerfherder/database-url` exists. Overcast adds `core-client-secret` and any others NF names. Use a task role for S3; leave static keys empty. | `terraform/modules/secrets/main.tf`; module `task_role_arn` |
| 8 | Artifact store | Dedicated bucket created by Overcast in `us-east-1`, versioned/encrypted/lifecycle per the Podbay export-bucket pattern; virtual-host addressing; S3 gateway endpoint avoids NAT. | `terraform/envs/staging/main.tf:827–884` |
| 9 | Database | PostgreSQL 16.13, no RDS Proxy, deletion protection on, 7-day backups (live read). TLS available; `rds.force_ssl` enforcement not verified. Single role `nerfherder_staging`; split migration/runtime roles not yet (same M-2 pattern as SF). **Capacity**: `db.t3.micro`, roughly 85 max connections shared by four databases; NF's 33-connection pool is a large fraction. Trim for staging or Overcast upsizes. | `services/dbbootstrap/bootstrap.sql`; `terraform/envs/staging/variables.tf:24–28` |
| 10 | Migrations | One-off RunTask, separate task-definition family (dbbootstrap/dbverify precedent). Trigger: operator today; a deploy-workflow step is an Overcast addition. Own execution role reading the migration DB leaf. | `terraform/envs/staging/main.tf:392, 527` |
| 11 | Health / DNS | Cloud Map without ALB target is supported (`target_group_arn` optional). `deploy-service.yml`'s public `/ready` check does not fit an internal-only service; Overcast must add an internal check variant. Orchestrator uses ECS container healthCheck on `/ready`; post-deploy check will read `/ready/detail`. | `.github/workflows/deploy-service.yml` "Verify health" |
| 12 | Image | No NF push role yet (module lists core/shuttleforge/podbay). Overcast adds `arclight-nerfherder` trusting `repo:arclightintel-dev/arclight-nerfherder:ref:refs/heads/main`. Tags `v1-<sha>`, immutable. Prod roles trust the obsolete owner (DR-8). | `terraform/modules/iam-github-oidc/main.tf:156–164` |
| 13 | Observability | Log group `/arclight/staging/nerfherder`; running-task alarm + SNS to `alarm_email` added like other services. Unauthenticated `/ready/detail` and `/metrics` inside the VPC acceptable; nothing internal reaches the ALB without a host rule. | `terraform/modules/observability/` |
| 14 | Bootstrap seeding | One-off RunTask with command override is the accepted pattern; execution role for secrets plus NF's own DB role; no operator AWS keys in the task. | dbbootstrap precedent |
| 15 | Event sink | No consumer exists (no bus/topic/queue for module events). `event_sink_mode = disabled` stands. | staging/prod roots |
| 16 | Governance | Charter "Nerfherder deployment: deferred" and D-056 §15 are Complex-owned; an O-series decision cannot lift them. Needs a small D-series amendment, then Overcast records the wiring as an O-decision. | `docs/CHARTER.md`; D-056 §15 |

## Overcast work implied (not scheduled)

New NF security group and rules; module variables for rollout percentages (shared with SF's O-2); Secrets Manager/KMS/SSM interface endpoints if fail-closed egress is required; `core-client-secret` shell and task role; artifact bucket; migration task family; NF ECR push role; internal-only post-deploy check in `deploy-service.yml`; log group and alarm. All wait on the owner's sequencing and the platform amendment in item 16.

## Follow-ups answered 2026-10-21 (five items from NF, via the owner)

| # | NF ask | Overcast answer | Evidence |
|---|---|---|---|
| 1 | Enable `rds.force_ssl` | Already enforced: `rds.force_ssl = 1` on parameter group `arclight-staging-pg16-20260624130504373200000002` (RDS PostgreSQL 16 engine default, in-sync); CA `rds-ca-rsa2048-g1`. Plaintext connects are refused today; Core already connects over TLS. No apply needed. | live `describe-db-parameters` 2026-10-21 |
| 2 | Separate migration and runtime roles, two leaves | Agreed with NF's naming: shell `nerfherder/migration-database-url` added beside `database-url`; existing `nerfherder_staging` (database owner) becomes the migration role; new DML-only `nerfherder_app_staging` backs `database-url`. Lands with NF's wiring change. | `terraform/modules/secrets/main.tf:19-20`; `services/dbbootstrap/bootstrap.sql:24-37` |
| 3 | NF trims its pool to 13 | Fine; no upsize for NF. `max_connections` = LEAST(DBInstanceClassMemory/9531392, 5000) = 112 on `db.t3.micro`; 24 h peak usage 3. Upsize when the committed sum approaches about 80. | live parameter + CloudWatch `DatabaseConnections` |
| 4a | RDS SG admits only service SGs | Confirmed: `sg-0098d9af3d843bfa1` has three ingress rules, tcp 5432 from the core, shuttleforge and dbbootstrap groups; no CIDR rules. NF's group becomes a fourth list entry. | live `describe-security-group-rules`; `terraform/modules/rds-postgres/main.tf:32-41` |
| 4b | Client behaviour during maintenance or failover | Single-AZ `db.t3.micro`, no failover. A reboot (maintenance window sat 09:43-10:13 UTC, auto minor upgrade on, class change) drops connections with TCP reset / refused for roughly 1-3 min, longer for a minor upgrade; loud, self-recovering. The silent case is a removed or broken SG path: packets dropped, no RST, client hangs until its own keepalive or timeout. Server-side `tcp_keepalives_idle` is engine default; `idle_in_transaction_session_timeout` 86400000 ms. NF owns client keepalives (about 30 s idle, 10 s interval, count 3) plus connect and statement timeouts. | live `describe-db-instances` and parameters |
| 4c | Bounded SG-rule removal demonstration | Acceptable: at most five minutes, NF's own ingress rule only, operator-run, restored by `terraform apply`, outside Core hours, owner's go at the time. Affects NF alone (rules are per source group). | same |
| 5 | Task size 1 vCPU / 2 GB | Valid Fargate pair; module takes plain numbers. Start there and measure. | `terraform/modules/ecs-service-fargate/variables.tf:53-63` |

Gate order on Overcast's side is unchanged: D-series amendment lifting the Nerfherder deployment deferral, then NF's wiring change, then the owner's apply.

