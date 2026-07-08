# Module Alignment Annex — Overcast

> **Module**: arclight-overcast
> **Date**: 2026-07-08
> **Re**: D-063, D-064, D-065 consultation
> **In-flight work**: coturn spec (v1.1-draft), Phase 6A Core deploy

---

## 1. Current state

### D-065 — spec-plan boundary

The coturn implementation spec (`docs/specs/coturn-implementation-spec.md`) is the live case study for D-065. After codex-1 reviewed the spec, hotpants was dispatched specifically to audit implementation gaps. Hotpants returned NO-GO with 6 BLOCKS-IMPLEMENTATION findings, all of which were "the spec describes behavior but doesn't contain literal code":

1. `vpc_cidr` CIDR-to-range shell conversion algorithm not specified
2. EIP-to-user-data Terraform interpolation path not shown
3. Render script specified behaviorally, not as a literal script
4. File write semantics (atomic move, ownership, permissions) not exact
5. systemd drop-in creation commands not given
6. Full replacement vs incremental patch unclear

D-065 confirms: **these belong in the plan, not the spec.** The coturn spec has the right behavioral contracts (what the render script must do, what the config must contain, what the failure behavior must be). The exact bash, exact HCL, and exact shell functions are plan-phase artifacts.

This means the coturn spec's current state — codex-1 CONDITIONAL-GO with all prior blockers PASS, all 12 sections LOCKED except §8/§10/§12 consistency concerns — is the correct completion state for a spec under D-065. The hotpants implementation gaps are the implementation plan's problem.

### D-063 — validation sections

The coturn spec has a verification contract (§10) with:
- Pre-implementation package probe (ran and passed, 11/11)
- Terraform plan expectations
- Runtime smoke tests (8 tests)
- Negative tests (7 tests)
- Podbay E2E smoke (3 scenarios)
- Coverage matrix (26 RQs + 7 BCs + 13 FMs mapped)

This is close to D-063 compliance but was not framed against D-052 tiers. The mapping would be:

| D-052 tier | Coturn coverage |
|-----------|----------------|
| Unit test (module CI) | `terraform validate`, `terraform plan` |
| Smoke test | SSM reachability, coturn service active, rendered config checks |
| Live/OVT | UDP/TCP allocation, negative auth tests, Podbay E2E |

The coturn spec should cite D-052 tier mapping. Will add in the plan or as a spec amendment.

### D-064 — PSDR

PSDR is new for Overcast. We have not been doing target experience validation — the closest analog was the Podbay team questions (RQ-POD-01–08) which validated the consumer's experience contract. But that was ad-hoc, not a structured PSDR pass.

For coturn, the target experience is narrow: Podbay gets an EIP and a shared secret, mints HMAC credentials, browser gets TURN relay. The PSDR question would be: "does the plan produce a working TURN relay that Podbay can consume with only those two outputs?" That's a useful check.

---

## 2. Impact

### Active specs/plans needing updates

| Artifact | D-065 impact | D-063 impact |
|----------|-------------|-------------|
| `docs/specs/coturn-implementation-spec.md` | Remove any residual implementation-level detail; accept hotpants gaps as plan-phase work | Add D-052 tier mapping to §10 |
| Coturn implementation plan (not yet written) | **New artifact** — must contain all literal code hotpants demanded | Must include validation section |
| Core Phase 6A deploy | No spec exists — this is operational, not new infrastructure | N/A |

### What changes

The biggest change: **the coturn spec process stops here.** The spec is done (pending codex-1 consistency fixes). Next artifact is the implementation plan, which is where the render script, Terraform snippets, CIDR conversion function, and systemd lifecycle code live.

This is a better outcome than trying to force literal code into the spec. The spec is stable and reviewable at the behavioral level; the plan is where implementation details get locked and reviewed.

### PSDR justification

PSDR is justified for coturn — the module has failed 4 implementation cycles. A 1-hour PSDR asking "does this plan actually produce a working TURN relay?" before implementation starts is the cheapest insurance against cycle 5.

PSDR is probably not justified for operational tasks (Core Phase 6A deploy, secret shell creation, env var additions). Those are execution, not design.

---

## 3. Edge cases and concerns

### Spec-plan boundary for infrastructure modules

For application modules (Core, Podbay, ShuttleForge), the spec-plan boundary is natural: spec says what the API does, plan says how the code implements it.

For infrastructure modules (coturn, VPC, ALB, ECS), the boundary is less obvious because the "code" is both the implementation AND the interface. A Terraform module's HCL is simultaneously the implementation (how resources are created) and the contract (what variables/outputs exist, what resources are managed). The coturn spec handles this by:
- Listing existing variables/outputs with code citations (spec concern — defines the interface)
- Marking proposed variables as PROPOSED (spec concern — extends the interface)
- Deferring exact HCL blocks to the plan (per D-065)

This works but the gray area is real. If a future spec reviewer demands to see the exact `aws_instance` block to verify the behavioral contract, D-065 says that's a plan-phase ask.

### Exploratory/research phases

Not applicable to Overcast currently. All active work has known implementation paths.

### PSDR scaling

PSDR should be required for:
- New infrastructure modules (coturn, future modules)
- Cross-module integration (Podbay workspace substrate, Core deploy pipeline)

PSDR should be optional for:
- Single-resource operational changes (new secret shell, env var addition)
- Pure Terraform refactors (no behavioral change)

Suggested threshold: required when the plan has > 3 items or touches > 1 module boundary.

---

## 4. Suggestions

D-065 resolves a real tension we hit this session. The coturn spec went through hotpants scoping → codex-2 structuring → claude-main writing → codex-1 verification → claude-core pre-completion check → codex-1 re-verification → hotpants implementation gap audit. The hotpants audit demanded literal code in the spec. D-065 says that's wrong — and it's right. The spec and plan serve different purposes, and forcing code into the spec made the spec harder to review for behavioral correctness.

One process note: the coturn spec process took 5 artifacts (scoping, skeleton, spec, research findings, Podbay answers) plus 3 review cycles. That's appropriate for a module with 4 prior failures. For simpler modules, the process should compress — a spec that can be written and reviewed in one pass shouldn't need 5 supporting artifacts.

No conflicts with Overcast's established workflow. D-063/D-064/D-065 are adopted starting now. Current in-flight coturn spec work completes under the current model; the implementation plan will be the first artifact under D-065.
