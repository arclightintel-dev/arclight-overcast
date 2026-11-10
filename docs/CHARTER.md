# Charter: Overcast (AWS Deployment Profile)

> This is a reference copy. The normative charter lives at:
> `arclight-complex/platform/boundary-charters/charter-overcast.md`
>
> Updated 2026-07-02 per D-058 (scope expansion) and D-059 (environment topology).
> Aligned 2026-11-10 with arclight-complex `48c1715`: no production environment in v1 (owner ruling 2026-11-09, D-056 parked); Podbay deferred to v2 (D-071); Nerfherder enabled on staging only (D-072). The normative charter at `48c1715` still lists Route 53, Podbay ECR repositories and a weaker staging auto-deploy rule; reported to Complex.

## Summary

Overcast is the AWS deployment substrate repository for the Arclight platform.

**Modules own what runs. Overcast owns where it runs.**

### Owns

- Infrastructure provisioning (VPC, ECS, RDS, ALB, ECR, IAM, Secrets Manager, CloudWatch)
- All environment infrastructure (staging, production, future dev/preview). v1 has staging only; production is parked
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
| D-056 | Production infrastructure spec (architecture, topology, security). Parked for v1 (owner ruling 2026-11-09) |
| D-058 | Overcast scope: frontend, domains, all environments, CI/CD deploy, developer access |
| D-059 | Environment topology: local + staging + prod, manual deploy trigger, hybrid CI/CD, SSO + OIDC. v1: staging is production (§9); no auto-deploy to staging while it carries operational material (§8) |
| D-071 | Podbay deferred to v2: no Podbay deployment is a v1 target |
| D-072 | Nerfherder deployment enabled on staging only; production remains deferred |
