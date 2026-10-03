# Corporate Terraform state

This root manages `arclight-corporate-terraform-state-650880817826` in AWS account `650880817826`, `us-east-1`. Corporate identity state needs a separate bucket because existing staging deploy roles can access the whole shared `arclight-terraform-state` bucket. This root grants no staging, production, or cross-account access. Existing account-level IAM permissions still apply.

The bucket has versioning, AES256 default encryption, public access blocking, bucket-owner-enforced ownership, and a policy denying non-TLS requests. Terraform prevents bucket destruction and never force-deletes its objects. Backend authentication uses the operator's AWS credentials independently of Entra authentication; neither credentials nor private certificate material belong in this root.

## One-time bootstrap

Use an authorized corporate administrator's AWS profile. Run these PowerShell commands from the repository root. Backend initialization requires the bucket to exist first: this root subsequently imports and manages that same bucket, storing its own state at `state/terraform.tfstate`.

```powershell
$env:AWS_PROFILE = 'default'
$corporateAccount = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0 -or $corporateAccount -ne '650880817826') {
    throw 'Expected AWS account 650880817826.'
}

# Run only for a new bucket. If it already exists, verify ownership and reconcile it.
aws s3api create-bucket --bucket arclight-corporate-terraform-state-650880817826 --region us-east-1
if ($LASTEXITCODE -ne 0) { throw 'Bucket creation failed; inspect before retrying.' }

aws s3api head-bucket --bucket arclight-corporate-terraform-state-650880817826 --expected-bucket-owner 650880817826 --region us-east-1
if ($LASTEXITCODE -ne 0) { throw 'Could not verify the expected bucket owner.' }

terraform -chdir=terraform/corporate/state init -input=false
if ($LASTEXITCODE -ne 0) { throw 'Backend initialization failed.' }
terraform -chdir=terraform/corporate/state import aws_s3_bucket.corporate_state arclight-corporate-terraform-state-650880817826
if ($LASTEXITCODE -ne 0) { throw 'Import failed; inspect state before retrying.' }
terraform -chdir=terraform/corporate/state plan '-out=corporate-state.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Plan failed.' }
terraform -chdir=terraform/corporate/state show corporate-state.tfplan
```

Review the saved plan before applying it. It should add bucket configuration resources and update bucket tags, with no bucket replacement or unrelated resources. Apply that exact plan with `terraform -chdir=terraform/corporate/state apply corporate-state.tfplan`. For an existing managed bucket, skip creation and import; inspect `terraform state list` and reconcile partial bootstrap before retrying. Import any pre-existing configuration that requires preservation rather than overwriting it.

The first state write uses S3's default encryption and the backend's explicit encryption request. Versioning and the explicit bucket policy begin when the configuration is applied; do not place Entra state in this backend until those settings are verified. Check `get-bucket-versioning`, `get-bucket-encryption`, `get-public-access-block`, `get-bucket-ownership-controls`, and `get-bucket-policy` using `aws s3api` with the bucket name and expected owner. The Entra bootstrap root uses the separate key `entra/bootstrap/terraform.tfstate`.

## Local validation

```powershell
terraform -chdir=terraform/corporate/state fmt -check
terraform -chdir=terraform/corporate/state init -backend=false -input=false
terraform -chdir=terraform/corporate/state validate
terraform -chdir=terraform/corporate/state providers lock -platform=windows_amd64 -platform=linux_amd64
```

These checks validate configuration and provider schemas; they do not establish the live backend. Keep the generated dependency lock file committed. Backend locking uses S3 lock objects and requires Terraform 1.10 or newer; no DynamoDB table is provisioned. See [HashiCorp's S3 backend documentation](https://developer.hashicorp.com/terraform/language/backend/s3) for separate state-object and lock-object permissions.
