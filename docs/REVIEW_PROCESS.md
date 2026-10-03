# Review Process

## When reviews are required

| Change type | Internal review | External review |
|-------------|----------------|-----------------|
| New Terraform module | claude-core + security | codex-1 + codex-2 + hotpants |
| IAM role/policy changes | Security reviewer | codex-1 (correctness) |
| Security group changes | Security reviewer | codex-2 (structural) |
| Secrets module changes | Security reviewer | codex-1 |
| Cross-environment module changes | claude-core | codex-2 (prod impact) |
| New service wiring | claude-core + contract auditor | Full external battery |
| Runbook changes | claude-core | hotpants (operational) |
| CI/CD workflow changes | claude-core | codex-2 |

## Documentation-only validation

Governance reconciliation and handoffs that do not change executable configuration use source/document checks: inspect applicable instructions and immutable evidence, check the diff and local links, and obtain a focused contract/ownership review where claims cross repositories. Do not run cloud-authenticated plans, apply infrastructure or exercise mutating endpoints solely to validate prose.

State what was newly checked, what is dated prior evidence, and what remains unverified. Preserve uncommitted work and use an explicit file allowlist for any later commit. Source-contract acknowledgment is not deployment or runtime acceptance.

## Infrastructure implementation protocol

1. **Implement** — write the code
2. **Self-verify** — `terraform validate`, `terraform fmt`, `terraform plan` for both staging AND prod
3. **Internal review** — dispatch claude-core and relevant specialist agents
4. **Fix findings** — address all FAIL items before external review
5. **External review** — provide prompts with required reading, specific checks, and GO/NO-GO gate
6. **Fix external findings** — address all FAIL items
7. **Apply** — `terraform apply` within the user's authorized scope, against the reviewed target/plan, after all required reviewers are GO. Review GO alone does not authorize an operation.

## Review prompt template

Every external review prompt must include:
- Context (what changed, why)
- Required reading (specific file paths)
- Specific checks (numbered, verifiable)
- `IMPORTANT: Do not trust summaries. Read the actual files. Cite file:line.`
- Output format: per-check PASS/FAIL, GO/NO-GO verdict

## Findings that block apply

- Any IAM policy that grants broader access than intended
- Any security group rule that opens unintended ingress
- Any secret value that would enter Terraform state
- Any resource that would modify staging state from prod (or vice versa)
- Any module change that causes unintended staging plan diff
