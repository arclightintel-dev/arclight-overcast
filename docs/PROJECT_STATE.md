# Project State

> Updated: 2026-07-10 | HEAD: `d1c9b7f` on `main`

## Current phase: Phase 5 (Podbay Deploy) — IN PROGRESS

### Phase summary

| Phase | Status | Key milestone |
|-------|--------|---------------|
| Phase 0 (Foundation) | COMPLETE | 158 staging resources, 4 databases bootstrapped |
| Phase 1 (Core Deploy) | COMPLETE | Core live at core.staging.arclight-complex.net |
| Phase 2 (CI/CD) | COMPLETE | 4 workflows, v2 merged to main |
| Phase 3 (Prod Environment) | COMPLETE | 139 prod resources, databases bootstrapped |
| D-059 §9 (Staging Hardening) | COMPLETE | All 7 items |
| Phase 5 (Podbay Deploy) | IN PROGRESS | coturn + controller LIVE (all checks green); workspace container exit-2 (Podbay-side) blocks E2E |
| Phase 4 (ShuttleForge) | BLOCKED | PostgreSQL support in arclight-shuttleforge |

### What's live on AWS

**Staging:**
- Core running (image v2-8c2f8c8, 19 tables, asset_backend ok, 4 asset tables, 6 asset permissions, SEAM-012 present, 2 platform owners, 3 IdP brokers)
- Podbay controller LIVE on Fargate (image v2-phase2-fix2, reachable at podbay.staging.arclight-complex.net, all ready checks green: database, jwks_cache, substrate_adapter ECSAdapter, connection_registry, seed_data, recipe_available)
- Podbay workspace substrate (task def v1-fix1 — was v1-initial with a chown bug, SG rules, execution role, controller task role, S3 export bucket, managed scaling)
- coturn TURN server LIVE (EIP 52.72.36.174, G4/G5 smoke passed, dedicated workspace subnets 10.0.30.0/24 + 10.0.31.0/24, allowed-peer-ip for workspace subnets, denied-peer-ip for all internal)
- Cloudflare Access gate live on *.staging.arclight-complex.net (one-time PIN IdP + service token for automation)
- Self-serve deploy pipeline live (deploy-service.yml — workflow_dispatch + repository_dispatch cross-repo)
- ALB restricted to Cloudflare CIDRs
- CloudTrail with deny-delete bucket policy

**Prod:**
- Substrate only — no services deployed
- RDS multi-AZ, ALB Cloudflare-restricted
- Databases bootstrapped, secrets shells created

### Deploy pipeline (CI/CD)

- `deploy-service.yml` supports both `workflow_dispatch` (manual) and `repository_dispatch` (cross-repo, module-triggered)
- Module repos self-serve deploys: push image to ECR, then fire `repository_dispatch` to Overcast
- OIDC trust allows `ref:main` + `environment:staging`
- Deploy role has `ecr:DescribeImages` + `PassRole` for both the execution and task roles
- Post-deploy health check authenticates through the Cloudflare Access service token
- `ecs-service-fargate` module sets `lifecycle { ignore_changes = [task_definition] }` so `terraform apply` does not revert pipeline-deployed images

### Blockers

| Item | Blocked on | Owner |
|------|-----------|-------|
| Podbay E2E integration smoke | Workspace container exits code 2 on launch (Podbay-side container issue, not infra) | Podbay |
| ShuttleForge deploy | PostgreSQL support in arclight-shuttleforge | ShuttleForge |
| IAM Identity Center | Google Workspace subscription | Owner (manual) |

### Next actions (priority order)

1. **Podbay E2E integration smoke** — blocked on Podbay-side fix for workspace container exit code 2 on launch
2. **ShuttleForge nudge** — one-file config change in arclight-shuttleforge
3. **Cloudflare Terraform** — highest-value infrastructure unification item
4. **IAM Identity Center** — when Google Workspace is set up

### Infrastructure notes

- EIP quota increased to 10
- CF Access service token (expires 2027-07-09) for automated staging checks
- OIDC trust fixed (arclightintel-dev)
- Dedicated workspace subnets added to VPC (10.0.30.0/24, 10.0.31.0/24)

### Open items from arclight-complex

- Infrastructure unification scoping (research complete, implementation pending)
- Core Phase 6A SM backend — response memorialized, awaiting 6A5
- Platform Operations Model — ratified, Overcast aligned
