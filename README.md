# arclight-overcast

AWS deployment substrate for the Arclight platform.

**Modules own what runs. Overcast owns where it runs.**

## What this repo is

Overcast is the AWS infrastructure provisioning, environment wiring, deployment automation, and operations repo for Arclight. It is NOT a product module — it has no domain nouns, no seam contracts, no API.

## What this repo is NOT

- Not application code (owned by module repos)
- Not platform governance or specs (owned by `arclight-complex`)
- Not a secrets store (creates shells; values populated out-of-band)

## Structure

```
terraform/
  modules/       # Reusable Terraform modules (VPC, ECS, RDS, etc.)
  envs/          # Per-environment configurations (staging, prod)
services/        # ECS task definition templates per module
docs/            # Charter, architecture decisions, runbooks
.github/         # CI/CD workflows
demo/            # Archived blackhole-hero visual demo
```

## Governing documents

- Charter: `docs/CHARTER.md`
- Infrastructure spec (D-056): `arclight-complex/docs/proposals/production-infrastructure-spec.md`
- Platform testing protocols: `arclight-complex/platform/specs/TESTING_PROTOCOLS.md`

## Prerequisites

- AWS account with IAM admin access
- Terraform >= 1.5
- AWS CLI v2
- GitHub CLI (for OIDC deploy setup)
