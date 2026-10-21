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
   Expect only additions (86 on 2026-10-21) and no change to any prod-owned object.
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

The host publishes `Arclight/Backstage Busy` every minute; the `idle-stop` alarm stops it after
30 zero minutes; the 07:00 America/New_York weekday schedule starts it. It never stops with a
running job, an open Portal, an operator session or a fresh deploy (owner decision D16). Set
`idle_stop_enabled = false` to keep it up, for example during migration.
