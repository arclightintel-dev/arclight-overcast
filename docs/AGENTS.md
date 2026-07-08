# Agent Team

Standing review team for Overcast infrastructure work.

## Internal agents

| Agent | Role | When to use |
|-------|------|-------------|
| **claude-core** (Opus 4.8) | Scope guard, drift detection, pre-completion verification | Post-compaction re-anchoring, scope checks on long batches, pre-commit verification |
| **Explore** | Read-only codebase search | Before any implementation — verify claims against actual code |
| **Security reviewer** | IAM, SG rules, secret handling, public surface audit | After any change touching IAM policies, security groups, or secrets |
| **Contract auditor** | Plan-vs-implementation alignment, doc-vs-reality | After implementation — verify docs match code |

## External reviewers

| Reviewer | Specialty | Invocation |
|----------|-----------|------------|
| **codex-1** (GPT-5.3-Codex) | Correctness — does the code match the plan | User-run via codex CLI |
| **codex-2** (GPT-5.4) | Structural — module boundaries, Terraform patterns | User-run via codex CLI |
| **hotpants** | Operational — will a human operator succeed with this | User-run, domain architect |

## Review dispatch rules

- **Always dispatch claude-core** after non-trivial implementation
- **Always dispatch security reviewer** for IAM, SG, or secrets changes
- **Always dispatch external reviewers** before applying infrastructure to staging or prod
- **Never trust agent summaries** — every claim must cite file:line from actual code
