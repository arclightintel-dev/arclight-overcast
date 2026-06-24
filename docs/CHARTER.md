# Charter: Overcast (AWS Deployment Profile)

> This is a reference copy. The normative charter lives at:
> `arclight-complex/platform/boundary-charters/charter-overcast.md`

## Summary

Overcast is the AWS deployment substrate repository for the Arclight platform.

**Modules own what runs. Overcast owns where it runs.**

### Owns

- Infrastructure provisioning (VPC, ECS, RDS, ALB, DNS, secrets shells, IAM)
- Environment wiring (staging, production)
- Deployment automation (CI/CD pipelines)
- Operational runbooks
- Observability configuration (CloudWatch, alarms)
- Backup configuration

### Does NOT own

- Module application code or Dockerfiles (module repos)
- Platform governance, specs, or contracts (arclight-complex)
- Secret values (shells only — values populated out-of-band)
- Domain logic, seam contracts, API design
- Module boot semantics or service discovery rules (implements conventions defined by Core/Foundation)

### Must NOT become

- A module (no API, no seam contracts, no domain nouns)
- A god-layer (no orchestration of module behavior)
- A monorepo (Dockerfiles stay in module repos)
- A secrets store (structure and permissions only)
- A shadow platform spec

See the full charter for service onboarding contract, drift risks, and governance model.
