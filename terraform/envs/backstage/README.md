# terraform/envs/backstage

Hosts Backstage (the owner's analyst application, repository `arclightintel-dev/podbay`) on one
Ubuntu 24.04 EC2 Docker host in the **prod** VPC, behind the **prod** ALB, under decision O-012.
This root owns only Backstage's resources. The VPC, the ALB and its HTTPS listener, and the
interface endpoints the host needs belong to `terraform/envs/prod` and are read through data
sources. State key `backstage/terraform.tfstate` in `arclight-terraform-state`.

| What | Where |
|---|---|
| Host bootstrap (first boot) | `templates/user-data.sh.tftpl`, embedding the scripts and units in `host/` |
| Run-time values (proxies, allowlists, buckets, grace) | SSM Parameter Store `/arclight/backstage/<env>/*` (`ssm.tf`); changing one never replaces the host |
| Secrets | four shells `arclight/backstage/<env>/*` (`secrets.tf`); values by the owner, never in Terraform |
| Deploy | `.github/workflows/deploy-backstage.yml` → `backstage-deploy <sha>` over SSM |
| Host specification, migration, cutover | [migrate-backstage.md](../../../docs/runbooks/migrate-backstage.md) |
| Deploys, rollback, idle-stop | [deploy-backstage.md](../../../docs/runbooks/deploy-backstage.md) |

## Applying (owner)

Every variable has a committed default; no `terraform.tfvars` is needed. Prod infrastructure is
operator-applied with admin credentials; the legacy CI workflows exclude this root.

1. **Prerequisite**: the prod root's five interface endpoints (Secrets Manager, SSM, ssmmessages,
   ec2messages, monitoring) are applied. Without them the host cannot read its parameters or
   secrets, and Session Manager does not work. This root looks the endpoints up, so its plan
   fails with "no matching VPC Endpoint found" until they exist.
2. **First apply, instance created**: `maintenance_egress` must be true, because first boot
   installs Docker, the AWS CLI and the CloudWatch agent from the internet.
   ```
   terraform init
   terraform plan -var=maintenance_egress=true -out=backstage-first.tfplan
   terraform apply backstage-first.tfplan
   ```
   Expect only additions (88 on a fresh account, 2026-10-22) and no change to any prod-owned object.
3. **Verify the boot** over Session Manager:
   `sudo cloud-init status --long`, `systemctl status backstage-data backstage-firewall docker backstage-network backstage-busy.timer`,
   `sudo iptables -S DOCKER-USER`, `sudo iptables -S BACKSTAGE-PORTAL-IN`, `findmnt /srv/backstage`.
   `backstage-compose` is skipped until the first deploy (no release yet).
4. **Second apply** with the default `maintenance_egress = false` closes the maintenance rules.

**Any change that replaces the instance** (user-data, the AMI on a deliberate refresh, the
instance type in some cases) needs `maintenance_egress = true` for that apply, then a closing
apply. The data volume survives replacement (`prevent_destroy`); the new instance mounts it.

## Manual, outside Terraform

- GitHub environment **`backstage`** on `arclightintel-dev/arclight-overcast`, with deployment
  branches restricted to `main`. The deploy role trusts only that environment, and it is root
  on the host.
- Cloudflare: proxied CNAME `backstage` → `alb_dns_name`, SSL mode Full (strict), a WAF skip for
  the hostname and WebSocket upgrades. No Cloudflare Access application (owner decision D19).
- Secret values, with `put-secret-value --secret-string` from a process variable and no trailing
  newline (the host refuses values with whitespace, quotes, backslashes or `$`).
- Entra: admin consent for `arclight-backstage`, the owner assigned `admin` first.

## Idle-stop

**Off since 2026-10-23: the host is always on (owner decision, O-012 note).** `idle_stop_enabled`
defaults to `false`, so the `idle-stop` alarm keeps evaluating but takes no action. The busy
publisher and the 07:00 America/New_York weekday start stay in place: the schedule is a no-op on a
running host and brings it back after a manual or maintenance stop.

With `idle_stop_enabled = true` the alarm stops the host after 30 zero minutes. It never stops with
a running job, an open Portal, an operator session or a fresh deploy (owner decision D16).

## Desktop downloads (WP6)

`downloads.tf`: private bucket `arclight-backstage-prod-downloads` (versioned, SSE-S3, public
access blocked, readable only by the CloudFront distribution through OAC), the distribution at
`backstage-downloads.arclight-complex.net` (the existing `*.arclight-complex.net` ACM certificate,
HTTPS only, GET/HEAD, caching from the objects' own `Cache-Control`), and the upload role
`arclight-backstage-prod-downloads-upload`. The role trusts exactly
`repo:arclightintel-dev/podbay:environment:desktop-release` and may only `s3:PutObject` on
`Backstage-Setup-*`; the workflow writes with `If-None-Match: *`, so a published version is never
replaced. Manual: a **DNS-only** Cloudflare CNAME `backstage-downloads` to
`downloads_distribution_domain` (CloudFront terminates TLS; a second CDN adds nothing), and the
owner sets `DESKTOP_DOWNLOADS_ROLE_ARN` and `DESKTOP_DOWNLOADS_BUCKET` (outputs) as variables on
the podbay `desktop-release` environment. The host has no egress to it. The login page's
download link (WP6 O7) should travel in the Backstage release bundle, not the host's `.env`
renderer: that renderer is in user data, so changing it replaces the instance.
