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
| **hotpants** | Domain architecture — domain coherence, taxonomy, ownership and operational fit | User-run, domain architect |

## Review dispatch rules

- **Always dispatch claude-core** after non-trivial implementation
- **Always dispatch security reviewer** for IAM, SG, or secrets changes
- **Always dispatch external reviewers** before applying infrastructure to staging or prod
- **Never trust agent summaries** — every claim must cite file:line from actual code

## Evidence discipline

- Pin the source revision for cross-repository reviews; distinguish it from the current checkout and uncommitted work.
- Report GO/NO-GO with PASS/WARN/FAIL for the checked scope. Source correspondence, producer-reported tests, fresh test execution, deployment and operational acceptance are separate evidence levels.
- Date provider observations. Documentation updates must not make historical account access, deployed images or connection checks appear freshly verified.
- Keep review receipts separate from canonical platform decisions. A candidate mechanism, review GO or delivered handoff does not select architecture or authorize operational changes.
- For documentation-only changes, use the read-only validation lane in [REVIEW_PROCESS.md](REVIEW_PROCESS.md). Preserve unrelated working changes.
