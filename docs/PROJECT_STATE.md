# Project State

> Updated: 2026-07-09 | HEAD: `e0dcac5` on `main`

## Current phase: Phase 5 (Podbay Deploy) — IN PROGRESS

### Phase summary

| Phase | Status | Key milestone |
|-------|--------|---------------|
| Phase 0 (Foundation) | COMPLETE | 158 staging resources, 4 databases bootstrapped |
| Phase 1 (Core Deploy) | COMPLETE | Core live at core.staging.arclight-complex.net |
| Phase 2 (CI/CD) | COMPLETE | 4 workflows, v2 merged to main |
| Phase 3 (Prod Environment) | COMPLETE | 139 prod resources, databases bootstrapped |
| D-059 §9 (Staging Hardening) | COMPLETE | All 7 items |
| Phase 5 (Podbay Workspace Substrate) | IN PROGRESS | coturn LIVE, Podbay controller LIVE, E2E smoke remaining |
| Phase 4 (ShuttleForge) | BLOCKED | PostgreSQL support in arclight-shuttleforge |

### What's live on AWS

**Staging:**
- Core running (image v2-d5a6e70, 19 tables, asset_backend ok, 4 asset tables, 6 asset permissions, SEAM-012 present, 2 platform owners, 3 IdP brokers)
- Podbay controller LIVE on Fargate (image v2-phase2-fix1, health OK, substrate ECSAdapter, JWKS cached)
- Podbay workspace substrate (task def, SG rules, execution role, controller task role, S3 export bucket, managed scaling)
- coturn TURN server LIVE (EIP 52.72.36.174, dedicated workspace subnets 10.0.30.0/24 + 10.0.31.0/24, allowed-peer-ip for workspace subnets, denied-peer-ip for all internal)
- Cloudflare Access gate live on *.staging.arclight-complex.net (one-time PIN IdP + service token for automation)
- ALB restricted to Cloudflare CIDRs
- CloudTrail with deny-delete bucket policy

**Prod:**
- Substrate only — no services deployed
- RDS multi-AZ, ALB Cloudflare-restricted
- Databases bootstrapped, secrets shells created

### Blockers

| Item | Blocked on | Owner |
|------|-----------|-------|
| Podbay E2E integration smoke | End-to-end workspace launch test | Overcast |
| ShuttleForge deploy | PostgreSQL support in arclight-shuttleforge | ShuttleForge |
| IAM Identity Center | Google Workspace subscription | Owner (manual) |

### Next actions (priority order)

1. **Podbay E2E integration smoke** — end-to-end workspace launch test through controller
2. **ShuttleForge nudge** — one-file config change in arclight-shuttleforge
3. **Cloudflare Terraform** — highest-value infrastructure unification item
4. **IAM Identity Center** — when Google Workspace is set up

### Infrastructure notes

- EIP quota increased to 10
- OIDC trust fixed (arclightintel-dev)
- Dedicated workspace subnets added to VPC (10.0.30.0/24, 10.0.31.0/24)

### Open items from arclight-complex

- Infrastructure unification scoping (research complete, implementation pending)
- Core Phase 6A SM backend — response memorialized, awaiting 6A5
- Platform Operations Model — ratified, Overcast aligned
