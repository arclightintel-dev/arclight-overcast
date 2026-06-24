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

### 2.2 DynamoDB table for state locking
```bash
aws dynamodb create-table \
  --table-name arclight-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2.3 Uncomment backend config
After creating the bucket and table, uncomment the `backend "s3"` block in
`terraform/envs/staging/backend.tf` and run `terraform init`.

## Step 3: Initial Resources

### 3.1 Route 53 hosted zone
```bash
aws route53 create-hosted-zone \
  --name <your-domain> \
  --caller-reference $(date +%s)
```
Note the NS records — you'll need them for DNS delegation.

### 3.2 ACM certificate
```bash
aws acm request-certificate \
  --domain-name "*.<your-domain>" \
  --subject-alternative-names "<your-domain>" \
  --validation-method DNS \
  --region us-east-1
```
Add the CNAME validation records to Route 53 (or your registrar).

### 3.3 ECR repositories
```bash
for repo in arclight/core arclight/shuttleforge arclight/podbay arclight/podbay-workspace-browser; do
  aws ecr create-repository \
    --repository-name "$repo" \
    --image-scanning-configuration scanOnPush=true \
    --region us-east-1
done
```

### 3.4 DNS delegation
If domain registered outside Route 53: add the NS records from step 3.1
to your registrar's DNS settings. Allow up to 48h for propagation.

## Step 4: First Terraform Run

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
