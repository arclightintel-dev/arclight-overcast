# Coturn TURN Module Implementation Spec Scaffold

> Structuring artifact for `claude-main`.
> This is a scaffold only: it defines headings, fields, evidence rules, conformance criteria, dependencies, and gates. It does not fill the implementation spec content.

## Discrepancy Notice

- Section count: the prompt expected 12 sections; `docs/specs/coturn-scoping.md:154-169` contains 12 required sections. No discrepancy.
- Research question count: the prompt expected 28 research questions; `docs/specs/coturn-scoping.md:38-71` contains 26 numbered research questions: 10 OS/package, 8 AWS/bootstrap, and 8 Podbay.
- Blocking condition count: the prompt expected 6 blocking conditions; `docs/specs/coturn-scoping.md:73-89` contains 7 blocking conditions.
- Failure mode count: the prompt expected 12 failure modes; `docs/specs/coturn-scoping.md:135-152` contains one lead failure mode, secret retrieval failure, plus 12 enumerated "other high-priority failure modes." This scaffold tracks the lead mode as `FM-00` and the enumerated modes as `FM-01` through `FM-12`.
- This scaffold is structured around the file contents actually present in `docs/specs/coturn-scoping.md`.

## 1. Section Skeleton

### 1.1 Source IDs Used In Mappings

These IDs are assigned only for this scaffold so that later spec work can map every open fact back to the scoping document.

#### Research Question IDs

| ID | Scoping source |
|---|---|
| `RQ-OS-01` | Ubuntu 24.04 AWS AMI, `apt-get install coturn`, and `universe` repo check (`docs/specs/coturn-scoping.md:40`) |
| `RQ-OS-02` | Installed `coturn.service` content (`docs/specs/coturn-scoping.md:41`) |
| `RQ-OS-03` | `/etc/default/coturn` and `TURNSERVER_ENABLED=1` behavior (`docs/specs/coturn-scoping.md:42`) |
| `RQ-OS-04` | Default runtime user and group (`docs/specs/coturn-scoping.md:43`) |
| `RQ-OS-05` | Package-created service account identity (`docs/specs/coturn-scoping.md:44`) |
| `RQ-OS-06` | Default ownership and permissions for config/default/data/log/userdb paths (`docs/specs/coturn-scoping.md:45`) |
| `RQ-OS-07` | Service enable/start behavior after install (`docs/specs/coturn-scoping.md:46`) |
| `RQ-OS-08` | Default generated secrets, CLI password, TLS material, or sample config state (`docs/specs/coturn-scoping.md:47`) |
| `RQ-OS-09` | Packaged support for `use-auth-secret` and `static-auth-secret` (`docs/specs/coturn-scoping.md:48`) |
| `RQ-OS-10` | Prometheus support or fallback to logs/systemd/blackbox probes (`docs/specs/coturn-scoping.md:49`) |
| `RQ-AWS-01` | AWS CLI v2 install path and unauthenticated runtime download decision (`docs/specs/coturn-scoping.md:53`) |
| `RQ-AWS-02` | SSM agent preinstall/enablement on selected Ubuntu AWS AMI (`docs/specs/coturn-scoping.md:54`) |
| `RQ-AWS-03` | Cloud-init and EIP association race (`docs/specs/coturn-scoping.md:55`) |
| `RQ-AWS-04` | Source of rendered `external-ip` (`docs/specs/coturn-scoping.md:56`) |
| `RQ-AWS-05` | IMDSv2 token handling and retry behavior (`docs/specs/coturn-scoping.md:57`) |
| `RQ-AWS-06` | Minimal IAM policy for coturn (`docs/specs/coturn-scoping.md:58`) |
| `RQ-AWS-07` | Outbound egress restriction decision (`docs/specs/coturn-scoping.md:59`) |
| `RQ-AWS-08` | Route53 record ownership decision (`docs/specs/coturn-scoping.md:60`) |
| `RQ-POD-01` | Podbay API endpoint returning TURN credentials to browser (`docs/specs/coturn-scoping.md:64`) |
| `RQ-POD-02` | Existing surface-grant object and fields (`docs/specs/coturn-scoping.md:65`) |
| `RQ-POD-03` | TURN username shape (`docs/specs/coturn-scoping.md:66`) |
| `RQ-POD-04` | Credential TTL rule (`docs/specs/coturn-scoping.md:67`) |
| `RQ-POD-05` | Workspace WebRTC server credential need and issuer (`docs/specs/coturn-scoping.md:68`) |
| `RQ-POD-06` | Rotation handling for credentials minted under previous shared secret (`docs/specs/coturn-scoping.md:69`) |
| `RQ-POD-07` | Clock skew assumptions across controller, coturn, and client (`docs/specs/coturn-scoping.md:70`) |
| `RQ-POD-08` | Credential minting logs and provenance without leaking secrets (`docs/specs/coturn-scoping.md:71`) |

#### Blocking Condition IDs

| ID | Scoping source |
|---|---|
| `BC-01` | Empirical OS/package verification on disposable EC2 using exact AMI filter and instance type family (`docs/specs/coturn-scoping.md:77`) |
| `BC-02` | Locked Podbay credential contract and issuer/secret exposure boundary (`docs/specs/coturn-scoping.md:79`) |
| `BC-03` | Populated TURN shared secret value before apply/start, including format, entropy, ownership, rotation, and readers (`docs/specs/coturn-scoping.md:81`) |
| `BC-04` | Locked endpoint model: EIP only, EIP plus DNS, or output consumed by a DNS module (`docs/specs/coturn-scoping.md:83`) |
| `BC-05` | Locked security policy: inbound, relay range, outbound, denied peers, SSM-only admin, no SSH, no CLI/web-admin, fallback/TLS decision (`docs/specs/coturn-scoping.md:85`) |
| `BC-06` | Locked bootstrap failure behavior; no accidental throwaway-secret fallback (`docs/specs/coturn-scoping.md:87`) |
| `BC-07` | Acceptance tests defined before code changes (`docs/specs/coturn-scoping.md:89`) |

#### Failure Mode IDs For Coverage Tracking

| ID | Scoping source |
|---|---|
| `FM-00` | Secret retrieval failure and throwaway-secret fail-dark behavior (`docs/specs/coturn-scoping.md:137`) |
| `FM-01` | EIP/public-IP race (`docs/specs/coturn-scoping.md:141`) |
| `FM-02` | Realm mismatch (`docs/specs/coturn-scoping.md:142`) |
| `FM-03` | Clock skew (`docs/specs/coturn-scoping.md:143`) |
| `FM-04` | Package behavior drift (`docs/specs/coturn-scoping.md:144`) |
| `FM-05` | Secret format mismatch (`docs/specs/coturn-scoping.md:145`) |
| `FM-06` | AWS CLI/SSM install failure (`docs/specs/coturn-scoping.md:146`) |
| `FM-07` | Security group incompleteness (`docs/specs/coturn-scoping.md:147`) |
| `FM-08` | Overbroad relay target access (`docs/specs/coturn-scoping.md:148`) |
| `FM-09` | Logging leaks (`docs/specs/coturn-scoping.md:149`) |
| `FM-10` | Restart/rotation mismatch (`docs/specs/coturn-scoping.md:150`) |
| `FM-11` | No negative tests (`docs/specs/coturn-scoping.md:151`) |
| `FM-12` | Abuse/reflection exposure (`docs/specs/coturn-scoping.md:152`) |

### 1.2 Required Section Order

The eventual implementation spec must use these headings in this order, matching `docs/specs/coturn-scoping.md:158-169`.

| No. | Exact section heading | Purpose | Research questions mapped | Blocking conditions mapped |
|---:|---|---|---|---|
| 1 | Decision authority | Anchor the spec to D-062/O-002/INV-005, identify locally available authority, and mark non-goals before implementation details are considered. | No direct RQ; this section governs acceptance of all RQs and must flag any D-062 claims that lack a cited arclight-complex source. | `BC-01` through `BC-07` as global gates; detailed closure is owned by later sections. |
| 2 | Runtime architecture | Define the infrastructure topology and ownership boundaries for EC2, subnet, EIP, DNS, security group, IAM, SSM, and observability. | `RQ-AWS-02`, `RQ-AWS-06`, `RQ-AWS-07`, `RQ-AWS-08`, `RQ-OS-10` | `BC-04`, `BC-05`, `BC-07` |
| 3 | OS/package contract | Lock exact OS, AMI selection, package source/version, package-installed files, systemd unit, runtime identity, permissions, and packaged capability. | `RQ-OS-01` through `RQ-OS-10` | `BC-01`, `BC-07` |
| 4 | Bootstrap contract | Specify first-boot sequence, dependency ordering, AWS CLI/SSM handling, EIP detection, secret fetch, config render, and systemd start. | `RQ-OS-03`, `RQ-OS-06`, `RQ-OS-07`, `RQ-AWS-01` through `RQ-AWS-05`, `RQ-AWS-06` | `BC-01`, `BC-03`, `BC-06`, `BC-07` |
| 5 | Steady-state contract | Specify restart, re-render, rotation, and runtime failure behavior after first boot. | `RQ-OS-02`, `RQ-OS-03`, `RQ-OS-07`, `RQ-OS-09`, `RQ-AWS-03`, `RQ-AWS-04`, `RQ-POD-06`, `RQ-POD-07` | `BC-03`, `BC-06`, `BC-07` |
| 6 | Coturn config contract | Define required and forbidden coturn options, realm, auth mode, external IP, relay range, CLI/web-admin posture, peer deny policy, and logging. | `RQ-OS-08`, `RQ-OS-09`, `RQ-OS-10`, `RQ-AWS-04`, `RQ-AWS-07`, `RQ-POD-03`, `RQ-POD-04`, `RQ-POD-07`, `RQ-POD-08` | `BC-03`, `BC-05`, `BC-06`, `BC-07` |
| 7 | Podbay integration contract | Define the Overcast/Podbay boundary, endpoint outputs, DNS contract, controller secret access, credential minting, TTL, username, and ICE config shape. | `RQ-AWS-08`, `RQ-POD-01` through `RQ-POD-08` | `BC-02`, `BC-03`, `BC-04`, `BC-07` |
| 8 | Secret custody contract | Define secret ARN/name, value format, entropy, KMS/IAM scope, readers, rotation runbook, and no-logging guarantees. | `RQ-OS-08`, `RQ-AWS-06`, `RQ-POD-06`, `RQ-POD-08` | `BC-02`, `BC-03`, `BC-06`, `BC-07` |
| 9 | Network/security contract | Define inbound and outbound network exposure, denied peer targets, no-SSH stance, SSM debug path, and abuse controls. | `RQ-AWS-02`, `RQ-AWS-06`, `RQ-AWS-07`, `RQ-AWS-08`, `RQ-POD-05` | `BC-04`, `BC-05`, `BC-07` |
| 10 | Verification contract | Define package probe, Terraform validation/plan expectations, runtime smoke tests, WebRTC E2E, negative auth tests, and observability checks. | `RQ-OS-01` through `RQ-OS-10`; `RQ-AWS-01` through `RQ-AWS-08`; `RQ-POD-01` through `RQ-POD-08` | `BC-01` through `BC-07` |
| 11 | Rollback contract | Define how to unwire coturn without orphaning EIP, secret, or DNS state, and how live Podbay sessions are handled. | `RQ-AWS-03`, `RQ-AWS-08`, `RQ-POD-01`, `RQ-POD-05`, `RQ-POD-06`, `RQ-POD-07` | `BC-02`, `BC-03`, `BC-04`, `BC-06`, `BC-07` |
| 12 | Open questions register | Track unresolved package, AWS, Podbay, DNS, security, rotation, and verification facts until each is closed or explicitly deferred. | `RQ-OS-01` through `RQ-OS-10`; `RQ-AWS-01` through `RQ-AWS-08`; `RQ-POD-01` through `RQ-POD-08` | `BC-01` through `BC-07` |

## 2. Contract Shape Per Section

Each section must split normative, source-backed claims from prose. A verifiable claim is any statement that selects behavior, asserts current behavior, names a real variable/output/resource/path, quotes a package/AWS/Podbay fact, defines an acceptance criterion, or constrains implementation. Verifiable claims must cite a source. Prose is limited to rationale, tradeoff explanation, and reader orientation; prose must not introduce uncited requirements.

### 1. Decision authority

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| Authority source table | Table: `Source`, `Local citation`, `Normative effect`, `Status` | O-002 local decision text from `docs/DECISIONS.md:19-25`; INV-005 from `docs/CONSTITUTION.md:27-37`; INV-004 if secret values/state are discussed from `docs/CONSTITUTION.md:23-25`; INV-006 if `aws_instance.user_data` is discussed from `docs/CONSTITUTION.md:39-41`; D-062 only after the actual arclight-complex source is cited. | Why the authority table exists and how readers should use it. |
| Non-goals | Enumerated list with `Non-goal`, `Reason`, `Source`, `Impact` | Any claim that a feature is out of scope, deferred, or owned by another repo/team. | Tradeoff rationale for keeping v1 narrow. |
| Implementation stop rule | Checklist | INV-005 and O-002 status that the module is not wired and needs a spec before reimplementation. | Short explanation of risk from prior apply failures. |

### 2. Runtime architecture

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| Topology inventory | Table: `Component`, `Owner`, `Current reference`, `Target decision`, `Source` | Current module facts from `terraform/modules/coturn/main.tf`, including security group ports (`:10-40`), IAM role/profile (`:49-102`), AMI lookup (`:108-121`), EC2 instance (`:127-233`), and EIP association (`:239-248`). AWS architecture assertions need AWS docs. | Architecture overview and rationale for chosen topology. |
| Module interface inventory | Table: `Name`, `Kind`, `Current/proposed`, `Consumer`, `Source` | Existing variable names only from `terraform/modules/coturn/variables.tf:1-36`; existing output names only from `terraform/modules/coturn/outputs.tf:1-14`; proposed names must be labeled `PROPOSED`. | Naming rationale. |
| Ownership boundary | Matrix: `Area`, `Overcast owns`, `Podbay owns`, `Shared handoff`, `Source` | Boundary claims from scoping document or Podbay team answers. | Explanation of why a boundary avoids authority leakage. |
| Observability path | Table: `Signal`, `Emitter`, `Transport`, `Reader`, `Retention`, `Source` | CloudWatch/logging/systemd/SSM claims require AWS docs, package probe output, or code citations. | Operational rationale for chosen signals. |

### 3. OS/package contract

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| OS/AMI decision record | Decision record: `Decision`, `Alternatives`, `Evidence`, `Implications`, `Status` | AMI filter/current code from `terraform/modules/coturn/main.tf:108-121`; OS/package requirements from INV-005; empirical AMI facts from package probe transcript or AWS docs. | Why the chosen OS is acceptable. |
| Package evidence table | Table: `Fact`, `Observed value`, `Probe command`, `Source artifact`, `Status` | Package repo/version, installed files, `coturn.service`, runtime user/group, accounts, default permissions, service enablement/start behavior, generated defaults. | Notes on why package drift matters. |
| Systemd/file contract | Table plus code block for excerpts only: `Path`, `Owner`, `Mode`, `Created by`, `Spec requirement`, `Source` | Unit/default-file behavior, file paths, ownership, and permissions from disposable EC2 probe. | Explanation of how file permissions support security goals. |
| Package capability record | Table: `Capability`, `Packaged support`, `Limitations`, `Source` | `use-auth-secret`, `static-auth-secret`, multi-secret behavior, Prometheus availability, and any unsupported options. | Tradeoff discussion for metrics strategy. |

### 4. Bootstrap contract

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| First-boot sequence | Numbered sequence table: `Step`, `Preconditions`, `Action`, `Failure behavior`, `Evidence source` | All claims about cloud-init, package install, AWS CLI, SSM, IMDSv2, EIP timing, secret fetch, config render, and systemd start. | Rationale for ordering. |
| Dependency ordering matrix | Table: `Dependency`, `Must complete before`, `Timeout/retry`, `On failure`, `Source` | EIP association and external IP facts; IMDSv2 token behavior; SSM agent install/enablement; AWS CLI install source. | Explanation of operator-visible failure design. |
| Render contract | Code block with placeholders plus table: `Input`, `Source`, `Validation`, `Forbidden fallback` | Secret retrieval, realm, external IP, relay ports, auth mode, file path, and no throwaway secret. | Why fail-hard behavior is preferred. |
| Terraform/user-data constraints | Table: `Terraform construct`, `Current code reference`, `Constitution constraint`, `Spec implication` | `aws_instance.user_data` facts and INV-006 when user-data encoding is discussed. | Rationale for any future AMI or cloud-init alternative. |

### 5. Steady-state contract

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| Restart/re-render matrix | Table: `Event`, `Inputs refreshed`, `Inputs cached`, `Expected result`, `Failure result`, `Source` | systemd restart behavior, `ExecStartPre` behavior, secret fetch result, config render path, public IP assumptions. | Why particular restart behavior is operationally acceptable. |
| Rotation state machine | State table or Mermaid state diagram plus source table | Single-secret or multi-secret behavior, old/new credential overlap, coturn session behavior, Podbay switch timing. | Tradeoff discussion between simple rotation and zero-downtime rotation. |
| Runtime failure policy | Table: `Failure`, `Detection`, `Service state`, `Operator signal`, `Recovery`, `Source` | Any rule about fail-hard, degraded state, cached last-known-good config, or alerting. | Rationale for fail-fast vs resilience. |
| Clock-skew handling | Table: `Actor`, `Clock source`, `Bound`, `Mitigation`, `Source` | Bounds and assumptions from Podbay/AWS/NTP evidence. | Explanation of user impact. |

### 6. Coturn config contract

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| Required option table | Table: `Option`, `Value/source`, `Reason`, `Verification`, `Source` | Required coturn options, realm, `use-auth-secret`, `static-auth-secret`, external IP, min/max relay ports, logging options, and any rate-limit options. | Rationale for selected defaults. |
| Forbidden option table | Table: `Option/surface`, `Forbidden state`, `Reason`, `Verification`, `Source` | CLI/web-admin exposure, default secrets, TLS material, sample config state, unauthenticated behavior, and any forbidden package defaults. | Explanation of security posture. |
| Rendered config template | Code block with placeholders only, never real secrets | Every option in the template must be backed by coturn docs, package probe, or current code reference. | Short comments explaining placeholders. |
| Peer policy table | Table: `CIDR/range`, `allow/deny`, `Reason`, `Source`, `Verification` | Denied peer CIDRs, link-local/metadata/RFC1918/VPC/RDS/private-service handling, and coturn deny/allow option support. | Threat model rationale. |
| Logging/redaction table | Table: `Log source`, `Allowed fields`, `Forbidden fields`, `Verification`, `Source` | Claims about log destinations and secret redaction. | Explanation of audit value. |

### 7. Podbay integration contract

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| Boundary matrix | Matrix: `Responsibility`, `Overcast`, `Podbay controller`, `Browser`, `Workspace`, `Source` | Credential issuer, authorization authority, shared secret readers, and workspace/browser exposure limits from scoping and Podbay team answer. | Rationale for keeping authorization outside infra. |
| Endpoint handoff | Table: `Field`, `Producer`, `Consumer`, `Format`, `Source`, `Status` | DNS/EIP endpoint, port, transport variants, realm, Terraform outputs, and any Podbay environment variables. Existing output names must cite `terraform/modules/coturn/outputs.tf:1-14`; proposed outputs must be labeled `PROPOSED`. | Discussion of DNS vs IP tradeoff. |
| Credential minting contract | Decision record plus pseudocode block with placeholders | Algorithm, username shape, credential TTL, grant binding, and clock skew must cite coturn docs and Podbay team answer. | Explanation of auditability choices. |
| ICE config schema | JSON schema or JSON example with placeholders | URLs, transport variants, username, credential, credential type, and realm/endpoint assumptions. | Explanation of client compatibility. |
| Podbay logging/provenance | Table: `Event`, `Fields allowed`, `Fields forbidden`, `Source` | Grant/workspace/principal/expiry/endpoint logging and secret/credential non-logging. | Rationale for forensic value. |

### 8. Secret custody contract

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| Secret inventory | Table: `Secret`, `Environment`, `Name/ARN`, `Value format`, `Owner`, `Readers`, `Source` | Existing variable `turn_secret_arn` from `terraform/modules/coturn/variables.tf:16-19`; Secrets Manager shell-only invariant from `docs/CONSTITUTION.md:23-25`; reader lists from IAM/Podbay sources. | Naming rationale. |
| Value format contract | Decision record: `raw string vs JSON`, `entropy`, `charset`, `validation`, `Status` | Format, entropy, restrictions, and validation must cite design decision and operator/source evidence. | Tradeoff rationale for raw vs JSON. |
| IAM/KMS matrix | Table: `Principal`, `Action`, `Resource`, `Condition`, `Reason`, `Source` | Existing coturn IAM reference from `terraform/modules/coturn/main.tf:71-97`; proposed controller access must cite Podbay/AWS decisions; KMS scope must cite AWS docs or policy review. | Explanation of least privilege intent. |
| Rotation runbook outline | Ordered checklist with evidence slots | Rotation actors, ordering, dual-secret or single-secret behavior, restart timing, and rollback points. | Operational rationale. |
| No-leak controls | Table: `Surface`, `Forbidden data`, `Control`, `Verification`, `Source` | No secret in Terraform state, cloud-init, journald, CloudWatch, shell trace, rendered output, browser, or workspace unless explicitly approved. | Rationale for redaction boundaries. |

### 9. Network/security contract

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| Inbound policy table | Table: `Protocol`, `Port/range`, `Source CIDR`, `Purpose`, `Verification`, `Source` | Current ingress facts from `terraform/modules/coturn/main.tf:10-32`; future port choices and TLS/TURNS deferral decisions. | Rationale for browser reachability. |
| Outbound policy table | Table: `Protocol`, `Destination`, `Purpose`, `Restriction`, `Verification`, `Source` | Current all-outbound reference from `terraform/modules/coturn/main.tf:34-40`; any egress restrictions. | Rationale for relay reachability. |
| Denied peer policy | Table: `Target class`, `CIDR/source`, `Decision`, `coturn option`, `Verification`, `Source` | Link-local, metadata, RFC1918, VPC CIDRs, RDS/private-service CIDRs, and any allowed peer exceptions. | Threat model explanation. |
| Admin/debug access | Table: `Access path`, `Allowed principal`, `Forbidden path`, `Source`, `Verification` | SSM-only, no SSH key path, no CLI/web-admin exposure, and SSM agent facts. | Operator workflow rationale. |
| Abuse/reflection controls | Table: `Risk`, `Control`, `Verification`, `Source` | Unauthenticated STUN/TURN behavior, rate limiting, and public UDP exposure controls. | Rationale for public-relay abuse posture. |

### 10. Verification contract

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| Pre-implementation package probe | Checklist/table: `Probe`, `Command`, `Expected evidence`, `Blocks`, `Artifact path` | Every `RQ-OS-*` closure and `BC-01`. | Why the probe prevents INV-005 repeats. |
| Terraform validation/plan expectations | Table: `Command`, `Expected result`, `Inspected resources`, `Failure examples` | `terraform validate`, plan assertions, exact variable/output names, and resource expectations from code. | Rationale for plan-level assertions. |
| Runtime smoke tests | Table: `Test`, `Method`, `Expected result`, `Failure mode covered`, `Evidence artifact` | SSM reachability, service active, rendered config, realm/external IP/auth mode/ports, UDP allocation, TCP fallback, CloudWatch/journald access. | Notes on manual vs automated execution. |
| Negative tests | Table: `Test`, `Invalid input`, `Expected failure`, `Failure mode covered`, `Evidence artifact` | Wrong secret, expired credential, realm mismatch, denied peer, and no secret leakage checks. | Rationale for negative coverage. |
| Podbay E2E smoke | Table: `Scenario`, `Podbay precondition`, `TURN expectation`, `Evidence`, `Owner` | Browser-to-workspace relay, credential minting, grant TTL, and logging assertions from Podbay team answer. | Explanation of user-visible readiness. |
| Coverage matrix | Table: `RQ/BC/FM ID`, `Verifying section`, `Verification artifact`, `Status` | Every `RQ-*`, `BC-*`, and `FM-*` status. | None; this is a normative checklist. |

### 11. Rollback contract

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| Unwire sequence | Ordered checklist: `Step`, `Owner`, `Precondition`, `Rollback command/change`, `Verification`, `Source` | How to remove wiring without orphaning EIP/secret/DNS or breaking consumers. | Rationale for ordering. |
| Resource retention matrix | Table: `Resource`, `Retain/destroy`, `Reason`, `Owner`, `Source`, `Verification` | EIP, DNS record, secret shell/value, IAM policy, security group, logs, and instance behavior. Existing resources must cite current code if present. | Tradeoff rationale for retaining stable endpoints. |
| Live session impact matrix | Table: `Session state`, `Expected impact`, `Podbay action`, `User-visible behavior`, `Source` | Effects on active credentials, workspaces, and browser sessions from Podbay team answer and rotation behavior. | Explanation of operator communication. |
| Re-entry criteria | Checklist | Conditions required before re-enabling after rollback. | Rationale for avoiding repeated failed apply cycles. |

### 12. Open questions register

| Required field/subsection | Required format | Verifiable claims requiring citations | Prose allowed without citation |
|---|---|---|---|
| Register table | Table with the exact columns defined in Part 5 | Each open question must map to one or more `RQ-*` or `BC-*` IDs and cite the scoping source. | None in the table. |
| Severity definitions | Enumerated definitions for `HARD-BLOCK` and `SOFT-BLOCK` | Severity rules must match the acceptance gate and blocking conditions. | Short rationale for severity taxonomy. |
| Status taxonomy | Enumerated statuses: `Open`, `Researching`, `Proposed`, `Resolved`, `Deferred` | Status meanings and closure requirements. | None. |
| Closure evidence rules | Checklist | Required source types: package probe, AWS doc, existing code, Podbay team answer, or design decision. | Explanation of why each evidence class is sufficient. |

## 3. Conformance Criteria Per Section

| Section | Locked criteria | Open criteria |
|---|---|---|
| 1. Decision authority | Locked only when every authority claim cites its source; O-002 and INV-005 are cited from local docs; any D-062-specific claim cites the actual arclight-complex source or is explicitly marked unresolved; non-goals do not contradict a cited decision; all `BC-*` gates are represented in the spec-level stop rule. | Open if any authority source is uncited; D-062 is treated as fully known without the actual source; a non-goal depends on an unresolved `HARD-BLOCK`; or the section allows implementation before `BC-01` through `BC-07` are closed. |
| 2. Runtime architecture | Locked only when every component, owner, interface, and observability path is cited; actual Terraform variables/outputs/resources are quoted only from current files; proposed interfaces are labeled `PROPOSED`; endpoint ownership closes `RQ-AWS-08` and `BC-04`; network/IAM/logging dependencies are handed to Sections 8, 9, and 10. | Open if any topology component, output, DNS ownership rule, IAM boundary, SSM path, or logging path lacks evidence; if actual and proposed Terraform names are mixed; or if `BC-04` remains unresolved. |
| 3. OS/package contract | Locked only when the disposable EC2 package probe records the exact AMI/filter, package repo/version, unit content, runtime user/group, service account, file ownership/permissions, default state, auth-secret support, and metrics support; each `RQ-OS-*` row is `Resolved`; `BC-01` is closed. | Open if any `RQ-OS-*` answer is missing, inferred from package listing alone, or not tied to the exact deployed AMI/package version; or if package behavior drift lacks a verification plan. |
| 4. Bootstrap contract | Locked only when the first-boot sequence has ordered steps, preconditions, timeouts, retry behavior, failure behavior, and evidence for AWS CLI/SSM/EIP/IMDS/secret/config/systemd handling; first boot without the real secret fails visibly; no throwaway-secret path remains. | Open if AWS CLI/SSM install path, EIP/external IP race, IMDSv2 handling, secret fetch, config render, or systemd start behavior is unresolved; or if `BC-06` remains open. |
| 5. Steady-state contract | Locked only when restart, re-render, rotation, cached-state if any, Podbay secret switch timing, clock skew, and failure alerts are specified and sourced; rotation behavior closes `RQ-POD-06`; all runtime failure modes have detection and recovery entries. | Open if steady-state secret retrieval, restart, rotation, clock skew, or degraded-state behavior depends on an unresolved package/Podbay/design answer. |
| 6. Coturn config contract | Locked only when every required and forbidden option is sourced to coturn docs, package probe, current code, or design decision; realm, auth mode, external IP, relay range, peer deny policy, logging, CLI/web-admin posture, and rate-limit decisions have verification checks; no real secret appears. | Open if any coturn option is selected by assumption; realm/endpoint/credential assumptions are not aligned with Podbay; denied-peer policy is unresolved; or logging/redaction controls are not testable. |
| 7. Podbay integration contract | Locked only when Podbay confirms the credential API, surface-grant fields, issuer, username shape, TTL rule, workspace credential need, rotation overlap, clock skew, logging fields, and shared secret access path; browser and workspace never receive the shared secret unless a cited decision explicitly changes that boundary. | Open if any `RQ-POD-*` answer is missing; controller secret access is not sourced; endpoint/DNS is unresolved; or ICE config shape includes uncited fields. |
| 8. Secret custody contract | Locked only when the secret exists as a populated out-of-band value before apply/start; value format, entropy, character restrictions, owner, readers, KMS/IAM scope, rotation runbook, and no-leak checks are sourced; INV-004 state constraints are explicitly satisfied. | Open if the spec allows a secret shell to stand in for a value; raw-vs-JSON format is unresolved; any reader is uncited; KMS/IAM scope is inherited without decision; or leak checks are not verifiable. |
| 9. Network/security contract | Locked only when inbound ports, relay range, outbound policy, denied peer CIDRs, SSM-only admin path, no SSH path, no CLI/web-admin exposure, TCP fallback, TLS/TURNS deferral if any, and abuse/reflection controls are sourced and testable. | Open if public ingress/egress, denied-peer policy, admin/debug path, or abuse mitigation is unresolved; or if current security group behavior is accepted without a cited decision. |
| 10. Verification contract | Locked only when every `RQ-*`, `BC-*`, and `FM-*` has a named verification artifact; required tests from scoping are present; commands/methods have expected outcomes; negative auth and no-leak tests are included; `BC-07` is closed before code changes. | Open if any mapped question/blocker/failure mode lacks a verification artifact; if only Terraform apply is used as acceptance; or if Podbay E2E and negative tests are undefined. |
| 11. Rollback contract | Locked only when unwire steps, retained/destroyed resources, live session behavior, Podbay coordination, secret/DNS/EIP handling, and re-entry criteria are sourced and testable. | Open if rollback can orphan EIP/secret/DNS state; live Podbay sessions are not accounted for; or re-entry criteria permit the same unresolved blockers to recur. |
| 12. Open questions register | Locked only when every unresolved item has an ID, blocked sections, severity, resolution method, owner/source class, and status; zero `HARD-BLOCK` rows remain `Open`, `Researching`, or `Proposed` at implementation start; any `SOFT-BLOCK` deferral cites an explicit design decision. | Open if any `RQ-*` or `BC-*` is missing from the register or coverage matrix; severity is absent; resolution method is ambiguous; or a `HARD-BLOCK` remains unresolved. |

## 4. Cross-Reference Map

| Source section | Feeds/dependent section | Contract passed forward |
|---|---|---|
| 1. Decision authority | All sections | Authority hierarchy, non-goals, implementation stop rule, and required source classes. |
| 2. Runtime architecture | 4. Bootstrap contract | EC2/subnet/EIP/IAM/SSM/logging topology that bootstrap must instantiate or consume. |
| 2. Runtime architecture | 7. Podbay integration contract | Endpoint, DNS, and output/interface shape consumed by Podbay. |
| 2. Runtime architecture | 9. Network/security contract | Current and target network surfaces, admin path, and IAM/security boundaries. |
| 2. Runtime architecture | 10. Verification contract | Plan/runtime resources that verification must inspect. |
| 3. OS/package contract | 4. Bootstrap contract | Package install behavior, service enablement, files, users, and permission assumptions. |
| 3. OS/package contract | 5. Steady-state contract | systemd restart behavior, re-render constraints, runtime user, and package capability limits. |
| 3. OS/package contract | 6. Coturn config contract | Supported coturn options, paths, permissions, metrics/logging capability. |
| 3. OS/package contract | 10. Verification contract | Package probe artifacts and drift checks. |
| 4. Bootstrap contract | 5. Steady-state contract | Initial rendered state, failure semantics, and restart baseline. |
| 4. Bootstrap contract | 8. Secret custody contract | Secret fetch input, validation expectations, and no-fallback rule. |
| 4. Bootstrap contract | 10. Verification contract | First-boot tests and failure-path probes. |
| 5. Steady-state contract | 7. Podbay integration contract | Rotation overlap and credential lifetime behavior. |
| 5. Steady-state contract | 8. Secret custody contract | Rotation ordering, restart behavior, and cached-state decision if any. |
| 5. Steady-state contract | 11. Rollback contract | Runtime behavior during unwire, restart, and re-entry. |
| 6. Coturn config contract | 7. Podbay integration contract | Realm, endpoint, auth mode, username/credential compatibility, and ICE URL assumptions. |
| 6. Coturn config contract | 9. Network/security contract | Relay port range, denied peer policy, CLI/web-admin exposure, and abuse controls. |
| 6. Coturn config contract | 10. Verification contract | Config assertions, allocation tests, negative auth tests, and no-leak checks. |
| 7. Podbay integration contract | 8. Secret custody contract | Controller secret access and prohibited client/workspace secret exposure. |
| 7. Podbay integration contract | 10. Verification contract | Browser-to-workspace E2E, credential minting checks, and Podbay logging assertions. |
| 7. Podbay integration contract | 11. Rollback contract | Live session behavior and Podbay coordination during unwire. |
| 8. Secret custody contract | 4. Bootstrap contract | Secret source, format, validation, IAM/KMS access, and failure behavior. |
| 8. Secret custody contract | 5. Steady-state contract | Rotation and restart behavior. |
| 8. Secret custody contract | 10. Verification contract | Secret existence, no-state-value, no-log-leak, and IAM/KMS tests. |
| 9. Network/security contract | 10. Verification contract | Ingress/egress, denied-peer, SSM-only, no-SSH, fallback, and abuse/reflection tests. |
| 10. Verification contract | 12. Open questions register | Evidence that closes RQs, BCs, and failure-mode coverage rows. |
| 11. Rollback contract | 10. Verification contract | Rollback rehearsal or dry-run evidence and post-rollback checks. |
| 12. Open questions register | All sections | Blocks or unlocks section conformance based on unresolved questions and severity. |

## 5. Open-Question Register Template

Use this empty table shape in Section 12 of the eventual implementation spec. Do not treat the example rows below as populated register content.

| Question ID | Section(s) it blocks | Blocking severity (HARD-BLOCK vs SOFT-BLOCK) | Resolution method (package probe / AWS doc check / Podbay team / design decision) | Status |
|---|---|---|---|---|
|  |  |  |  |  |

Severity and status rules:

- `HARD-BLOCK`: unresolved item prevents implementation start because it blocks any `BC-*`, changes security/secret/bootstrap/Podbay contract behavior, or prevents a section from meeting its locked criteria.
- `SOFT-BLOCK`: unresolved item is non-v1, explanatory, or operationally deferrable only after an explicit design decision states why implementation may proceed.
- Allowed statuses: `Open`, `Researching`, `Proposed`, `Resolved`, `Deferred`.
- `Resolved` requires a cited source and the affected section's locked criteria must pass.
- `Deferred` requires a cited design decision, owner, follow-up trigger, and proof that no `HARD-BLOCK` acceptance gate is bypassed.

EXAMPLE rows only:

| Question ID | Section(s) it blocks | Blocking severity (HARD-BLOCK vs SOFT-BLOCK) | Resolution method (package probe / AWS doc check / Podbay team / design decision) | Status |
|---|---|---|---|---|
| EXAMPLE `RQ-AWS-03` | 4. Bootstrap contract; 6. Coturn config contract; 10. Verification contract | HARD-BLOCK | package probe / AWS doc check / design decision | Open |
| EXAMPLE `BC-03` | 4. Bootstrap contract; 5. Steady-state contract; 8. Secret custody contract; 10. Verification contract | HARD-BLOCK | design decision / Podbay team | Open |

## 6. Acceptance Gate

Implementation may begin only when every checklist item is true:

- [ ] The spec contains all 12 required sections in the exact order from `docs/specs/coturn-scoping.md:158-169`.
- [ ] The discrepancy between the prompt counts and the actual scoping-file counts is acknowledged in the spec or companion review note: 26 research questions, 7 blocking conditions, and `FM-00` plus `FM-01` through `FM-12`.
- [ ] Every `RQ-OS-*`, `RQ-AWS-*`, and `RQ-POD-*` has a `Resolved` row or an explicitly approved `Deferred` row in the open-question register.
- [ ] Zero `HARD-BLOCK` rows remain `Open`, `Researching`, or `Proposed`.
- [ ] All `BC-01` through `BC-07` are closed by cited evidence or cited design decisions.
- [ ] Every verifiable claim in every section has a source citation: package probe, package repository, AWS documentation, existing Terraform code, governance/decision document, or Podbay team answer.
- [ ] All references to existing Terraform variable names and output names cite `terraform/modules/coturn/variables.tf:1-36` or `terraform/modules/coturn/outputs.tf:1-14`; all new names are labeled `PROPOSED`.
- [ ] The spec does not treat the existing coturn module as authority; it uses `terraform/modules/coturn/*` only as reference evidence for current attempted implementation.
- [ ] INV-005 is satisfied for OS, package repo/install method, systemd units, runtime user, config files, ownership/permissions, bootstrap sequence, and failure modes.
- [ ] INV-004 is satisfied: Terraform may create secret shells, but no secret values are placed in Terraform state.
- [ ] INV-006 is addressed if `aws_instance.user_data` remains part of the implementation path.
- [ ] O-002 is cited for the local Overcast decision that coturn is self-hosted on EC2 with EIP per environment and currently not wired pending a spec.
- [ ] D-062-specific claims cite the actual arclight-complex D-062 source, not only the local O-002 summary.
- [ ] The Podbay/Overcast boundary is locked: controller-side credential issuance, browser receives only ephemeral ICE credentials, and workspace/shared-secret exposure is either forbidden or explicitly justified by a cited decision.
- [ ] The secret custody contract proves a populated secret value exists before apply/start and defines format, entropy, readers, KMS/IAM scope, rotation, and no-leak controls.
- [ ] The endpoint model is locked: EIP only, EIP plus DNS, or output consumed by a DNS module; Podbay-facing consumption is explicitly defined.
- [ ] The security policy is locked: inbound control and relay ports, outbound policy, denied peer CIDRs, no SSH, SSM debug path, no CLI/web-admin exposure, TCP fallback, and any TLS/TURNS deferral.
- [ ] Bootstrap failure behavior is locked: first boot and restart without the real secret fail visibly, unless a last-known-good strategy is separately specified with permissions, logging, and verification.
- [ ] All failure modes `FM-00` through `FM-12` map to at least one control and at least one verification artifact.
- [ ] Verification includes, at minimum, Terraform validate/plan, SSM reachability, coturn service active, rendered config checks, valid HMAC allocation, expired/wrong-secret failures, browser-to-workspace WebRTC smoke, and no secret leakage in logs.
- [ ] Rollback is defined for unwiring without orphaning EIP, secret, or DNS state, and includes live Podbay session behavior.
- [ ] The final spec has no normative placeholder language in locked sections; all remaining placeholders are confined to `SOFT-BLOCK` deferred rows with cited deferral decisions.
