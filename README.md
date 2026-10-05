# arclight-overcast

Infrastructure and deployment substrate for the Arclight platform.

**Modules own what runs. Overcast owns where it runs.**

## What this repo is

Overcast owns AWS infrastructure provisioning, environment wiring, deployment automation, corporate identity infrastructure, and operations for Arclight. It is not a product module. Corporate identity uses separate Terraform state and administrator-controlled bootstrap credentials; see the Entra management runbook below.

## What this repo is NOT

- Not application code (owned by module repos)
- Not platform governance or specs (owned by `arclight-complex`)
- Not a secrets store (creates shells; values populated out-of-band)

## Structure

```
terraform/
  modules/       # Reusable Terraform modules (VPC, ECS, RDS, etc.)
  envs/          # Per-environment configurations (staging, prod)
  corporate/     # Corporate state backend and Entra management identity
services/        # ECS task definition templates per module
docs/            # Charter, architecture decisions, runbooks
.github/         # CI/CD workflows
```

## Governing documents

- Current status and next actions: [Project state](docs/PROJECT_STATE.md)
- Latest handoff: [2026-10-03](docs/handoff/2026-10-03-handoff.md)
- Infrastructure providers, account inventory, and connection status: [Service registry](docs/service_registry.md)
- Corporate identity operations: [Entra management runbook](docs/runbooks/manage-entra.md)
- Core integration review and ownership: [7G/7F receipt](docs/platform-interface/module-feedback/core-phase7-integration-response.md)
- Charter: `docs/CHARTER.md`
- Infrastructure spec (D-056): `arclight-complex/docs/proposals/production-infrastructure-spec.md`
- Platform testing protocols: `arclight-complex/platform/specs/TESTING_PROTOCOLS.md`

## Prerequisites

- AWS account with IAM admin access
- Terraform >= 1.5
- AWS CLI v2
- GitHub CLI (for OIDC deploy setup)
