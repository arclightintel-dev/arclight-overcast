# Runbook: Initial AWS Bootstrap

## Prerequisites

- AWS account with root MFA enabled
- IAM admin user (not root) for day-to-day operations
- AWS CLI v2 configured (`aws configure`)
- Terraform >= 1.5 installed
- Domain name chosen

## Step 1: AWS Account Security Baseline

### 1.1 Root account MFA
- Sign in as root → IAM → Security credentials → MFA → Assign MFA device
- Use a hardware key or authenticator app (not SMS)
- Store recovery codes offline

### 1.2 IAM admin user
- IAM → Users → Create user
- Attach `AdministratorAccess` policy
- Enable MFA on this user
- Use this user for all subsequent work (never root)

### 1.3 Billing alerts
- Billing → Budgets → Create budget
- Set $500/month warning (adjust to your threshold)
- Alert at 80% and 100% of budget
- SNS notification to ops email

## Step 2: Terraform State Backend

### 2.1 S3 bucket for state files
```bash
aws s3api create-bucket \
  --bucket arclight-terraform-state \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket arclight-terraform-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket arclight-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

aws s3api put-public-access-block \
  --bucket arclight-terraform-state \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### 2.2 State locking — S3 native lockfile (no DynamoDB)

The backend uses S3 native lockfile locking (`use_lockfile = true` in
`terraform/envs/staging/backend.tf`), **not** a DynamoDB lock table. There is no
`arclight-terraform-locks` table to create — bucket versioning (2.1) plus the
native lockfile provide locking. If you are on an older Terraform that predates
`use_lockfile`, upgrade rather than adding DynamoDB.

### 2.3 Backend config

`backend.tf` ships with the `backend "s3"` block active (bucket
`arclight-terraform-state`, key `staging/terraform.tfstate`, `use_lockfile = true`).
After the bucket exists, run `terraform init`.

## Step 3: Initial Resources

> **DNS is Cloudflare, not Route 53.** `arclight-complex.net` is hosted on
> Cloudflare (see CLAUDE.md). Overcast does **not** create a Route 53 hosted zone;
> `terraform/envs/staging/main.tf` reads the ACM cert via a `data` source and
> restricts ALB ingress to Cloudflare IP ranges. The Route 53 steps below are
> retained only as a generic reference for a Route 53-hosted domain — for the
> live setup, do the DNS/validation work in Cloudflare.

### 3.1 Hosted zone (Cloudflare, or Route 53 if self-hosting DNS)
For the live domain, the zone already exists in Cloudflare — nothing to create.
(Route 53 alternative, only if you host DNS in AWS:)
```bash
aws route53 create-hosted-zone \
  --name <your-domain> \
  --caller-reference $(date +%s)
```

### 3.2 ACM certificate
The staging cert is `*.staging.<domain>` (+ the apex as SAN), DNS-validated.
```bash
aws acm request-certificate \
  --domain-name "*.staging.<your-domain>" \
  --subject-alternative-names "staging.<your-domain>" \
  --validation-method DNS \
  --region us-east-1
```
Add the CNAME validation records **in Cloudflare** (for the live domain), then
wait for status `ISSUED`. `main.tf` consumes the issued cert via
`data "aws_acm_certificate"`.

### 3.3 ECR repositories
ECR repos are **Terraform-managed** (`module.ecr`, wired in `main.tf`) and are
created by the first `terraform apply` (Step 4) — you normally do not create them
by hand. The managed set includes `arclight/core`, `arclight/shuttleforge`,
`arclight/podbay`, `arclight/podbay-workspace-browser`, and `arclight/dbbootstrap`.
Manual creation is only needed to bootstrap an image (e.g. `dbbootstrap`) before
the first apply.

### 3.4 DNS delegation
For a Cloudflare-hosted domain, ensure the registrar points to Cloudflare's
nameservers (one-time, already done for the live domain). No Route 53 delegation
is used.

## Step 4: First Terraform Run

> **Applies are currently manual.** The `terraform-apply.yml` CI auto-apply
> (push to `main`) is **not operational** right now — every apply this cycle was
> run locally. `terraform.tfvars` is gitignored (holds the real values), so the
> local working copy is the source of truth for apply:
>
> ```
> cd terraform/envs/staging
> C:\Tools\terraform.exe apply
> ```
>
> Both `terraform-plan.yml` and `terraform-apply.yml` are currently broken
> in CI (same root cause — cross-variable validation block rejected by CI's
> pinned Terraform `~> 1.5`). Do not assume any CI pipeline runs until the
> deployment-model rework lands.

```bash
cd terraform/envs/staging
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with actual values
terraform init
terraform plan
terraform apply
```

## Step 5: First Service (Core)

See `docs/runbooks/deploy-service.md` for deploying Core as Tier 0.
