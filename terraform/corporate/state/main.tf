resource "aws_s3_bucket" "corporate_state" {
  bucket        = "arclight-corporate-terraform-state-650880817826"
  force_destroy = false

  tags = {
    Project   = "arclight"
    Scope     = "corporate"
    ManagedBy = "terraform"
    Purpose   = "terraform-state"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "corporate_state" {
  bucket = aws_s3_bucket.corporate_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "corporate_state" {
  bucket = aws_s3_bucket.corporate_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "corporate_state" {
  bucket = aws_s3_bucket.corporate_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "corporate_state" {
  bucket = aws_s3_bucket.corporate_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "corporate_state" {
  bucket = aws_s3_bucket.corporate_state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.corporate_state.arn,
        "${aws_s3_bucket.corporate_state.arn}/*",
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}
