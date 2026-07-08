# Project State

> Updated: 2026-07-08 | HEAD: `6095dfa` on `v2` and `main`

## Current phase: Phase 5 (Podbay Deploy) — IN PROGRESS

### Phase summary

| Phase | Status | Key milestone |
|-------|--------|---------------|
| Phase 0 (Foundation) | COMPLETE | 158 staging resources, 4 databases bootstrapped |
| Phase 1 (Core Deploy) | COMPLETE | Core live at core.staging.arclight-complex.net |
| Phase 2 (CI/CD) | COMPLETE | 4 workflows, v2 merged to main |
| Phase 3 (Prod Environment) | COMPLETE | 139 prod resources, databases bootstrapped |
| D-059 §9 (Staging Hardening) | COMPLETE | All 7 items |
| Phase 5 (Podbay Workspace Substrate) | IN PROGRESS | 7/8 items done, coturn rolled back |
| Phase 4 (ShuttleForge) | BLOCKED | PostgreSQL support in arclight-shuttleforge |

### What's live on AWS

**Staging:**
- Core running (image v1-bfdf2ea, 2 platform owners, 3 IdP brokers)
- Podbay workspace substrate (task def, SG rules, execution role, controller task role, S3 export bucket, managed scaling)
- ALB restricted to Cloudflare CIDRs
- CloudTrail with deny-delete bucket policy

**Prod:**
- Substrate only — no services deployed
- RDS multi-AZ, ALB Cloudflare-restricted
- Databases bootstrapped, secrets shells created

### Blockers

| Item | Blocked on | Owner |
|------|-----------|-------|
| coturn TURN server | Needs spec before reimplementation | Overcast |
| ShuttleForge deploy | PostgreSQL support in arclight-shuttleforge | ShuttleForge |
| Podbay controller deploy | Podbay Batch 5 code completion | Podbay |
| IAM Identity Center | Google Workspace subscription | Owner (manual) |

### Next actions (priority order)

1. **coturn spec + reimplementation** — spec OS/package/systemd/bootstrap, then implement once
2. **ShuttleForge nudge** — one-file config change in arclight-shuttleforge
3. **Cloudflare Terraform** — highest-value infrastructure unification item
4. **IAM Identity Center** — when Google Workspace is set up

### Open items from arclight-complex

- Infrastructure unification scoping (research complete, implementation pending)
- Core Phase 6A SM backend — response memorialized, awaiting 6A5
- Platform Operations Model — ratified, Overcast aligned
