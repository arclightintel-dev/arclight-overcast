# migration: the one-time PC-to-host copy, plus archive/ for the 11.9 GB of validation copies
#            and backups the owner chose to keep off the host (OW-4).
# litestream: continuous replication of podbay.db and control.sqlite (O-012 item 5).
# deploy:    per-commit deploy bundles uploaded by Backstage CI (compose, litestream.yml,
#            images.json); the host copies <sha>/ into its own release directory.
locals {
  buckets = {
    migration  = { versioned = true }
    litestream = { versioned = false }
    deploy     = { versioned = true }
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket = "${local.name}-${each.key}"

  # Replicated databases and the migration copy are not regenerable.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = { for k, v in local.buckets : k => v if v.versioned }

  bucket = aws_s3_bucket.this[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "tls_only" {
  for_each = aws_s3_bucket.this

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      each.value.arn,
      "${each.value.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  policy = data.aws_iam_policy_document.tls_only[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "migration" {
  bucket = aws_s3_bucket.this["migration"].id

  rule {
    id     = "archive-to-glacier-ir"
    status = "Enabled"
    filter {
      prefix = "archive/"
    }
    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }
  }

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "litestream" {
  bucket = aws_s3_bucket.this["litestream"].id

  # Litestream manages its own generations and retention (litestream.yml).
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "deploy" {
  bucket = aws_s3_bucket.this["deploy"].id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
