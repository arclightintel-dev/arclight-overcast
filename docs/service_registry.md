# Infrastructure and deployment service registry

Documentation updated: 2026-10-03. Provider observations and bootstrap verification: 2026-09-30. Repository baseline: `5c3a93c`. No provider state was refreshed for this documentation update.

This is the inventory of infrastructure providers, account boundaries, management access, and unfinished connections. Record identifiers and secret references here; keep credential values in their secret store. Platform decisions remain in arclight-complex and implementation decisions remain in [DECISIONS.md](DECISIONS.md).

Resume from the [current handoff](handoff/2026-10-03-handoff.md). The [Core 7G/7F receipt](platform-interface/module-feedback/core-phase7-integration-response.md) separately records the blocked application-custody design; the AWS vault recommendation below does not establish SEAM-012 enforcement or authorize that backend.

## Current direction

Confirmed by the user on 2026-09-30:

- Microsoft Azure / Microsoft Entra ID provides the main corporate identity and SSO. Microsoft services hold corporate documents; the particular Microsoft 365 services still need identification.
- The primary corporate domain is `ansanalytics.com`. Microsoft tenant `27564b9c-b516-4bc4-9aa5-5692a38a1116` is `ANS Analytics LLC`, and the management account is `john@arclightlabs.io`. Authenticated Graph reads verified the tenant, default domain, account, and Global Administrator membership on 2026-09-30.
- Cloudflare provides web hosting. Existing DNS, TLS, and Access configuration are also part of its infrastructure role.
- A new GitHub enterprise / organization / identity setup exists separately from the current repository owner. Continue using the current account and repositories until a later migration.
- AWS remains the deployment and hosting platform.
- Finish Azure identity/management access and Cloudflare connections before taking on further infrastructure work.

Older references to Google Workspace as the planned workforce IdP are historical. Microsoft Entra is now the intended workforce IdP. This does not itself remove Google's existing application-login integration in Core or change any live authentication policy.

## Providers

| Service | Purpose | Account or tenant | State and next step |
|---|---|---|---|
| Microsoft Entra ID | Workforce directory, SSO, enterprise applications, group assignments | Tenant `27564b9c-b516-4bc4-9aa5-5692a38a1116` (`ANS Analytics LLC`); default domain `ansanalytics.com`; manager `john@arclightlabs.io` | Administrator access and certificate-authenticated management API access verified. Terraform owns the management identity. The user-approved `Application.ReadWrite.OwnedBy` grant is active; automation authority is limited to application management, not general directory administration. |
| Microsoft Azure / Microsoft 365 | Corporate services and documents; Azure resource administration where used | Same verified Entra tenant; verified domains `ANSAnalytics.onmicrosoft.com`, `ansanalytics.com`, `arclightlabs.io` | Microsoft license SKUs listed below. CLI login produced a tenant-level account, with no resource subscription selected; this is not proof the organization has no subscriptions. Document-service usage still needs inventory. |
| Cloudflare, account CF-01 | Four DNS zones; staging Access gate; user-reported web hosting | `76088d2d8df3d24e8808c3d26aeea51e` | Token active; zone and Access metadata readable. Pages project listing returns HTTP 403. Entra is absent from the returned Access IdP list. |
| Cloudflare, account CF-02 | `arclightintel.com` DNS; other uses unverified | `611f3fe83443e7743151c5d7b6dbf540` | Token active; zone metadata readable. Access and Pages listings return HTTP 403. Confirm whether this account remains separate. |
| GitHub, current | Active source repositories, Actions build/deploy, AWS OIDC | Authenticated account `arclightintel-dev`; this repo is `arclightintel-dev/arclight-overcast` | Authentication verified. Keep this repository owner and existing deployment trust in place until migration. Organization membership/admin authority not established by login alone. |
| GitHub, new enterprise | Future corporate repository and identity boundary | Enterprise slug, organization slug, and account model awaiting confirmation | User-confirmed existence. Determine personal accounts with SAML versus Enterprise Managed Users before configuring federation or planning migration. |
| AWS | ECS, EC2, RDS, ECR, VPC/ALB, IAM, S3, CloudWatch/CloudTrail, ACM, deployment infrastructure | Account `650880817826`, management account of Organization `o-626c11uior` (management email `arclightintel@gmail.com`); working region `us-east-1` | STS identity verified. Current local principal is IAM user `john-admin`. Read-only IAM inventory on 2026-10-05: three IAM users (`john-admin`, `sam-admin`, and the owner's personal `arclight-dev`), one group `Administrators`, root MFA enabled; details and deviations in [DEVELOPMENT.md](DEVELOPMENT.md). Entra federation and replacement of routine IAM-user access remain pending. |
| AWS Secrets Manager | Existing application/runtime secret store | Same AWS account and region; `arclight/staging/*`, `arclight/prod/*` | Live metadata listing returned 36 Arclight secret entries. No secret values read; population and consumer access were not tested. Recommended home for shared deployment credentials as well. |
| Corporate Terraform state | Corporate backend and Entra management-identity state | S3 `arclight-corporate-terraform-state-650880817826`, `us-east-1`; keys `state/terraform.tfstate` and `entra/bootstrap/terraform.tfstate` | Provisioned and managed by Terraform. Versioning, AES256 encryption, owner-enforced ownership, public-access blocking, and TLS-only policy verified. Staging Terraform role simulation denied Get/Put/Delete on the Entra state object. |

Cloudflare Workers service listings returned no services in either account for the credentials used. This is a bounded API result, not proof that all hosting products are absent. Pages inventory is still inaccessible by API; however, GitHub check runs on 2026-10-03 identify one Pages project, `arclight-labs` in CF-01, connected to this repository and building on push. Its builds failed on PR #6 and on merge commit `00c93d8`; the failure cause is unread because the logs are dashboard-only.

Authenticated Microsoft license inventory returned `FLOW_FREE` (1 consumed / 10,000 enabled), `EXCHANGESTANDARD` (4 / 4), `O365_BUSINESS_PREMIUM` (2 / 3), `POWER_BI_STANDARD` (1 / 1,000,000), and `SHAREPOINTSTANDARD` (4 / 4). These are raw SKU identifiers and capacity counts, not a claim that every product or federation feature is configured.

Existing app registrations before the new management bootstrap: Bright Data, backstage, Arclight Core Staging, P2P Server, Anthropic, and Arclight Core Dev. They were inventoried, not imported or modified.

New management application: `arclight-overcast-entra-management`; client ID `0027ad40-c6ab-4166-b010-6b9d378b1772`; application object ID `f2a9a871-28ee-419a-9181-946c2f5df58c`; service-principal object ID `4c5c3d64-2425-494f-b3f9-fec7253e842a`. The administrator owns both objects. Bootstrap configuration: [Entra Terraform root](../terraform/corporate/entra/bootstrap/README.md). Operation and rotation: [management runbook](runbooks/manage-entra.md).

Effective Graph permission: exactly `Application.ReadWrite.OwnedBy`, app-role ID `18a4783c-866b-4cc7-a460-3d5e5662c884`, resource service principal `9c81fdef-f0ad-4e04-888e-87e6c4656d6a`. Administrator granted it after explicit user approval on 2026-09-30 at 15:22 UTC; assignment ID `ZD1cTCUkT0mz-f7HJT6EKiwUJojQwk9MiNUfduDaywI`. Grant custody remains outside the automation-managed Terraform state.

## Cloudflare domains

All five zones below returned `active` on 2026-09-30. Zone status does not establish application health, registrar ownership, or correct DNS targets.

| Domain | Account | Zone ID | Known role |
|---|---|---|---|
| `arclight-complex.net` | CF-01 | `0f8d0f55f4873252390ed99f611f3f1a` | Platform service domain; staging Access application covers `*.staging.arclight-complex.net`. |
| `arclightcomplex.com` | CF-01 | `5d5da8b5b30c65d3528919654d6e226a` | Purpose and redirect policy to confirm. |
| `arclightlabs.io` | CF-01 | `0577f94cb13431aeacfb9d94488c6cc1` | Domain of the intended Microsoft management account. July canonical-domain reference is historical; the user now identifies `ansanalytics.com` as primary. |
| `nerfherder.io` | CF-01 | `7ab362df342d2f7a9e4b2d938885cabe` | Purpose and hosting project to confirm. |
| `arclightintel.com` | CF-02 | `b952008ddaf2e395fe5027bf942eebd6` | Purpose and intended account placement to confirm. |

The primary corporate domain, `ansanalytics.com`, was not returned by either accessible Cloudflare zone listing. Public DNS on 2026-09-30 returned nameservers `ns1.wordpress.com`, `ns2.wordpress.com`, and `ns3.wordpress.com`, plus MX priority 0 `ansanalytics-com.mail.protection.outlook.com`. This establishes public delegation and mail routing, not registrar ownership or management access. Its DNS remains a separate connection to identify; no DNS migration is implied.

CF-01 Access application: `a378347b-e740-4d07-877b-892268ed395b`, type `self_hosted`. Its account IdP listing contains `cloudflare` and `onetimepin`; no Entra provider was returned. Cloudflare dashboard SSO is a separate connection and was not inspected.

## Secret-store recommendation

Use **AWS Secrets Manager as the primary deployment and runtime vault**, with Entra governing human access through AWS IAM Identity Center. This builds on the store already used by the application infrastructure and gives non-AWS deployment credentials a central home without adding a second vault immediately. This is a recommendation, not a provisioned migration or a ratified new platform decision.

| Option | Fit for this setup | Disposition |
|---|---|---|
| AWS Secrets Manager | Runtime secrets already referenced by ECS. Can also hold Cloudflare API credentials, a GitHub App private key, and other automation credentials. GitHub Actions can authenticate to AWS using OIDC and retrieve only the secrets its role permits. | Recommended primary vault. Keep existing runtime paths and scope new automation access separately. |
| Azure Key Vault | General-purpose secrets, keys, and certificate service with Entra authentication and Azure RBAC. | Valid alternative for a corporate automation vault if Azure custody is preferred. Entra being the IdP alone does not require moving AWS runtime secrets. Avoid two competing authoritative copies. |
| GitHub Actions secrets | Repository, organization, and environment secrets consumed by workflows. | Keep workflow-specific/bootstrap secrets here where necessary. Prefer OIDC for cloud authentication and retrieve centrally managed values when needed. Do not use it as the organization-wide retrieval/administration vault. |
| Cloudflare secrets | Workers secrets and account Secrets Store bindings for supported Cloudflare workloads. | Use for workloads that need local Cloudflare bindings. The Secrets Store overview currently labels it open beta; it is not the proposed cross-provider vault. |

Human passwords, MFA recovery material, and emergency access need a separate recovery arrangement that remains usable if ordinary SSO fails. The team's password-manager choice is unknown. Do not put recovery values in this registry.

### Existing credentials and proposed custody

| Credential class | Current reference | Consumer / access | Next step |
|---|---|---|---|
| Application DB, signing, encryption, IdP, and TURN secrets | AWS `arclight/{environment}/{service}/*` | ECS execution-role injection; Podbay task role separately reads the TURN secret at runtime | Preserve current consumer contracts. Inventory rotation and access without reading values into documentation. |
| DB bootstrap passwords | AWS `arclight/{environment}/dbbootstrap/*` | Bootstrap execution role | Entries still appear in the live inventory. Confirm retention needs before deleting or rotating. |
| Cloudflare API token CF-01 | Local `.arclight/cloudflare_api_token` | Authenticated zone and Access reads | Token expires `2028-07-08T23:59:59Z`. Record exact grants, provision the needed hosting read access, and choose a central vault reference. |
| Cloudflare API token CF-02 | Local `.arclight/cloudflare_api_token_2` | Authenticated zone reads | Token expires `2027-07-08T23:59:59Z`. Account Access/Pages reads are denied; resolve only the permissions required for its intended role. |
| Cloudflare Access automation token | Local `.arclight/cf_access_service_token.env`; workflow references `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` | Staging readiness checks | Local file existence and workflow references verified; value, live deployment, and expiry not rechecked. |
| GitHub local CLI authentication | OS keyring used by `gh` | Current signed-in account | Keep existing authentication during the transition. Future enterprise login is a separate connection. |
| GitHub Actions to AWS | GitHub OIDC provider and scoped AWS roles | Deployment/image workflows | Already defined in Terraform. Current workflow execution was not tested. New repository ownership will require an explicit trust update at migration time. |
| Entra management | Azure CLI `2.90.0` and Microsoft Graph Authentication `2.41.0` in local `.arclight/tools`; administrator and application sessions verified | Certificate generated outside the repository with restricted filesystem ACLs, encrypted PFX, and Windows DPAPI-protected password; public certificate registered in Entra and expires `2027-03-29T14:50:32Z` | Bootstrap and approved Graph grant complete. Application-only certificate session successfully read application and service-principal inventories. No private key or password enters Terraform. |

Terraform continues to create secret containers and permissions only, per INV-004. Do not add secret values through Terraform resources or data sources that persist them in state. If a consumer requires a separate copy, record its source, delivery method, owner, and rotation procedure.

## Connections to finish

| Connection | Current evidence | Completion evidence |
|---|---|---|
| Local management to Entra | Complete for the initial application-management scope: Terraform bootstrap provisioned, exact approved Graph grant verified, and application-only certificate authentication successfully read both application and service-principal inventories | Subsequent work: configure/import selected owned applications in a separate automation-authenticated root. Existing applications have not yet been transferred to automation ownership or tested with automation writes. |
| Entra to AWS workforce access | `sso-admin list-instances` returned no instances visible to this principal in `us-east-1` | Correct AWS Organizations/Identity Center instance and home region established; Entra SAML/SCIM configured; test-user sign-in and temporary CLI access work with intended permission sets. The regional empty result does not exclude instances elsewhere. |
| Entra to Cloudflare Access | CF-01 has a staging app and one-time PIN; no Entra IdP in its returned list | Entra application and Cloudflare IdP configured; intended user/group admitted; unauthorized test identity denied; existing automation health check still works. |
| Entra to Cloudflare dashboard | Not inspected | Corporate email domain confirmed; separate dashboard SSO configured and tested before enforcement. Confirm which administrators/accounts it affects. |
| Management to Cloudflare hosting | Tokens authenticate; Pages listing denied in both accounts. One project is known indirectly: `arclight-labs` (CF-01) builds this repository via the GitHub app and has been failing since 2026-10-03. | Required account/project inventory readable; actual hosting projects, build source/branch and deployment identities recorded; the `arclight-labs` build failure explained or the integration deliberately retired. Test write authority only through the approved concrete configuration change. |
| Cloudflare configuration to Terraform | Prior adoption work was recorded at `stash@{0}`; active roots have no Cloudflare provider configuration | Re-identify the stash by message and content before use; its index may change. Inspect and reconcile the existing work, inventory intended resources, import existing configuration, and review a plan that preserves intended DNS, Access, and hosting behavior. |
| Entra to new GitHub enterprise | New setup reported; identifiers/account model unknown | Correct enterprise/org and personal-account versus EMU model confirmed; SSO/provisioning tested there. Existing repositories continue operating until separately planned migration. |
| Deployment credentials to central vault | AWS runtime store exists; Cloudflare management tokens currently local | Vault decision made; scoped secret references and authorized consumers recorded; retrieval tested without printing values; rotation/recovery ownership recorded. |

Execution order: confirm tenant/domain and management access; inventory identity and Cloudflare settings; implement and test the selected connections; centralize deployment credentials; then resume other infrastructure work. GitHub repository migration is a later task.

## Verification record

On 2026-09-30, inventory checks and subsequent authorized provisioning established:

- AWS CLI `default` profile authenticated as `arn:aws:iam::650880817826:user/john-admin`; authentication does not prove any particular administrative permission.
- AWS Secrets Manager metadata listed 19 staging and 17 prod entries under `arclight/` in `us-east-1`; no values were retrieved. RDS-managed secrets outside that prefix are excluded from this count.
- GitHub CLI authenticated as `arclightintel-dev`, using the local keyring. Repository origin remains `https://github.com/arclightintel-dev/arclight-overcast.git`.
- Cloudflare token verification, zone enumeration, and the selected account metadata calls produced the scoped results above. HTTP 403 is recorded as inaccessible, not as an empty inventory.
- Microsoft public OIDC discovery using the supplied tenant UUID, `ansanalytics.com`, and `arclightlabs.io` returned the same tenant issuer. This verifies public routing, not authenticated domain verification, tenant default-domain status, account membership, or administrative roles.
- Azure CLI authenticated as `john@arclightlabs.io`, user object `bf345fac-567a-4d8f-9883-6f1879935718`; Graph confirmed the tenant, three verified domains, `ansanalytics.com` as default, and Global Administrator role membership. Six application registrations and the license inventory above were readable.
- The subsequent user-authorized Terraform setup imported the dedicated bucket and manages six S3 resources. Five Entra resources created the management identity, ownership, certificate, and requested API access. Both roots returned no changes on authenticated post-apply plans. Existing application configuration, DNS, SSO policies, and repository ownership have not changed.
- After explicit user approval, the administrator granted `Application.ReadWrite.OwnedBy`; a fresh read confirmed exactly one Graph app-role assignment matching that scope. A certificate-authenticated `AppOnly` session successfully paginated `/v1.0/applications` (7 registrations) and `/v1.0/servicePrincipals` (364 objects). This verifies those API reads; no automation-authenticated write probe was performed.

Refresh the relevant row after every connection or migration. Keep observed state, user direction, and proposed configuration distinct.

## Sources

Local implementation: [secrets module](../terraform/modules/secrets/main.tf), [GitHub OIDC roles](../terraform/modules/iam-github-oidc/main.tf), [staging root](../terraform/envs/staging/main.tf), [deploy workflow](../.github/workflows/deploy-service.yml), [constitution](CONSTITUTION.md), and [July handoff](handoff/2026-07-10-handoff.md). The handoff is historical; live observations above take precedence for observed account state.

Provider documentation checked on 2026-09-30:

- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html) and [retrieval from GitHub Actions with OIDC](https://docs.aws.amazon.com/secretsmanager/latest/userguide/retrieving-secrets_github.html).
- [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview) and [Entra authentication](https://learn.microsoft.com/en-us/azure/key-vault/general/authentication).
- [GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).
- [Cloudflare Secrets Store](https://developers.cloudflare.com/secrets-store/), [Entra integration](https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/entra-id/), and [dashboard SSO](https://developers.cloudflare.com/fundamentals/manage-members/dashboard-sso/).
- [Entra to AWS IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/idp-microsoft-entra.html) and [Microsoft Graph PowerShell authentication](https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands).
- [GitHub enterprise account models](https://docs.github.com/en/enterprise-cloud@latest/admin/concepts/identity-and-access-management/enterprise-managed-users) and [adding existing organizations](https://docs.github.com/en/enterprise-cloud@latest/admin/managing-accounts-and-repositories/managing-organizations-in-your-enterprise/adding-organizations-to-your-enterprise).
