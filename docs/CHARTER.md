# Charter: Overcast (AWS Deployment Profile)

> This is a reference copy. The normative charter lives at:
> `arclight-complex/platform/boundary-charters/charter-overcast.md`
>
> Updated 2026-07-02 per D-058 (scope expansion) and D-059 (environment topology)

## Summary

Overcast is the AWS deployment substrate repository for the Arclight platform.

**Modules own what runs. Overcast owns where it runs.**

### Owns

- Infrastructure provisioning (VPC, ECS, RDS, ALB, ECR, IAM, Secrets Manager, CloudWatch)
- All environment infrastructure (staging, production, future dev/preview)
- Deployment automation (CI/CD deploy workflows — module repos own build/test)
- Developer access provisioning (IAM Identity Center, OIDC trust policies)
- Frontend web application deployment (S3 + CloudFront or Fargate)
- All domain management (Cloudflare DNS, ACM certificates, SSL/TLS configuration)
- Operational runbooks
- Observability configuration (CloudWatch, CloudTrail, alarms)
- Backup configuration

### Does NOT own

- Module application code or Dockerfiles (module repos)
- Platform governance, specs, or contracts (arclight-complex)
- Secret values (shells only — values populated out-of-band)
- Domain logic, seam contracts, API design
- Module boot semantics or service discovery rules
- Domain registration or transfer (Cloudflare account-level)
- Build or test workflows (module repos own these per D-059)

### Must NOT become

- A module (no API, no seam contracts, no domain nouns)
- A god-layer (no orchestration of module behavior)
- A monorepo (Dockerfiles stay in module repos)
- A secrets store (structure and permissions only)
- A shadow platform spec

See the full charter for service onboarding contract, drift risks, and governance model.

## Governing Decisions

| Decision | Summary |
|----------|---------|
| D-056 | Production infrastructure spec (architecture, topology, security) |
| D-058 | Overcast scope: frontend, domains, all environments, CI/CD deploy, developer access |
| D-059 | Environment topology: local + staging + prod, manual deploy trigger, hybrid CI/CD, SSO + OIDC |
