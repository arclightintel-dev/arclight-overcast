# Desktop downloads (Backstage WP6; O-012 later-PR list): a private bucket readable only by a
# CloudFront distribution at backstage-downloads.<domain>, and an upload role for Backstage's
# desktop-release workflow. Installers are public by design (analysts' browsers fetch them);
# the host never does, so there is no host egress. Names are versioned and the workflow writes
# with If-None-Match, so a published installer is never replaced and needs no invalidation.

locals {
  downloads_host = "${var.downloads_hostname}.${var.domain_name}"
}

data "aws_acm_certificate" "wildcard" {
  domain      = "*.${var.domain_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_s3_bucket" "downloads" {
  bucket = "${local.name}-downloads"

  # The run artifact expires after 30 days; after that this bucket is the only copy.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "downloads" {
  bucket                  = aws_s3_bucket.downloads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "downloads" {
  bucket = aws_s3_bucket.downloads.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "downloads" {
  bucket = aws_s3_bucket.downloads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "downloads" {
  bucket = aws_s3_bucket.downloads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_cloudfront_origin_access_control" "downloads" {
  name                              = "${local.name}-downloads"
  description                       = "Backstage Desktop downloads bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "downloads" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = "PriceClass_100"
  comment         = "Backstage Desktop downloads"
  aliases         = [local.downloads_host]

  origin {
    origin_id                = "downloads"
    domain_name              = aws_s3_bucket.downloads.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.downloads.id
  }

  # Caching follows the objects' own Cache-Control (one year, immutable); installers are
  # already compressed.
  default_cache_behavior {
    target_origin_id       = "downloads"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "https-only"
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.wildcard.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

data "aws_iam_policy_document" "downloads_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.downloads.arn,
      "${aws_s3_bucket.downloads.arn}/*",
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

  statement {
    sid       = "CloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.downloads.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.downloads.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "downloads" {
  bucket = aws_s3_bucket.downloads.id
  policy = data.aws_iam_policy_document.downloads_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.downloads]
}

# Upload role for the desktop-release workflow. The job runs in a GitHub environment, so its
# OIDC subject names the environment, not a ref.
data "aws_iam_policy_document" "downloads_upload_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.backstage_repository}:environment:${var.desktop_release_environment}"]
    }
  }
}

resource "aws_iam_role" "downloads_upload" {
  name               = "${local.name}-downloads-upload"
  assume_role_policy = data.aws_iam_policy_document.downloads_upload_trust.json
}

resource "aws_iam_role_policy" "downloads_upload" {
  name = "put-installers"
  role = aws_iam_role.downloads_upload.id

  # PutObject only: no Get, List or Delete. The workflow's If-None-Match write needs nothing more.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PutInstallers"
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = ["${aws_s3_bucket.downloads.arn}/Backstage-Setup-*"]
    }]
  })
}
