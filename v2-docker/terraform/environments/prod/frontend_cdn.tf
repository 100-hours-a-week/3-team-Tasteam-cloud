# ──────────────────────────────────────────────
# Frontend CDN — S3 (private) + CloudFront (OAC)
# ──────────────────────────────────────────────

locals {
  frontend_use_custom_certificate = var.frontend_cloudfront_certificate_arn != "" && length(var.frontend_cloudfront_aliases) > 0
}

resource "aws_s3_bucket" "frontend_static" {
  bucket = var.frontend_static_bucket_name

  tags = {
    Name    = "${var.environment}-frontend-static"
    Purpose = "frontend-static-hosting"
  }
}

resource "aws_s3_bucket_ownership_controls" "frontend_static" {
  bucket = aws_s3_bucket.frontend_static.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_static" {
  bucket = aws_s3_bucket.frontend_static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend_static" {
  bucket = aws_s3_bucket.frontend_static.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.environment}-frontend-oac"
  description                       = "OAC for ${var.environment} frontend static bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "frontend_index_no_cache" {
  name        = "${var.environment}-frontend-index-no-cache"
  comment     = "No edge cache for index/default route"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_cache_policy" "frontend_assets_immutable" {
  name        = "${var.environment}-frontend-assets-immutable"
  comment     = "Long cache for fingerprinted assets"
  default_ttl = 31536000
  max_ttl     = 31536000
  min_ttl     = 86400

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_response_headers_policy" "frontend_index_no_cache" {
  name    = "${var.environment}-frontend-index-no-cache"
  comment = "Set no-cache headers for HTML entrypoint"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      override = true
      value    = "no-cache, no-store, must-revalidate"
    }
  }
}

resource "aws_cloudfront_response_headers_policy" "frontend_assets_immutable" {
  name    = "${var.environment}-frontend-assets-immutable"
  comment = "Set immutable cache headers for static assets"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      override = true
      value    = "public, max-age=31536000, immutable"
    }
  }
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.environment} frontend static distribution"
  default_root_object = "index.html"
  price_class         = "PriceClass_200"
  aliases             = local.frontend_use_custom_certificate ? var.frontend_cloudfront_aliases : []

  origin {
    domain_name              = aws_s3_bucket.frontend_static.bucket_regional_domain_name
    origin_id                = "frontend-static-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "frontend-static-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    cache_policy_id            = aws_cloudfront_cache_policy.frontend_index_no_cache.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.frontend_index_no_cache.id
  }

  ordered_cache_behavior {
    path_pattern           = "assets/*"
    target_origin_id       = "frontend-static-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    cache_policy_id            = aws_cloudfront_cache_policy.frontend_assets_immutable.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.frontend_assets_immutable.id
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  dynamic "viewer_certificate" {
    for_each = local.frontend_use_custom_certificate ? [1] : []
    content {
      acm_certificate_arn      = var.frontend_cloudfront_certificate_arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = local.frontend_use_custom_certificate ? [] : [1]
    content {
      cloudfront_default_certificate = true
    }
  }

  tags = {
    Name    = "${var.environment}-frontend-cdn"
    Purpose = "frontend-static-cdn"
  }
}

data "aws_iam_policy_document" "frontend_static_cloudfront_read" {
  statement {
    sid = "AllowCloudFrontReadOnly"

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend_static.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend_static" {
  bucket = aws_s3_bucket.frontend_static.id
  policy = data.aws_iam_policy_document.frontend_static_cloudfront_read.json

  depends_on = [
    aws_s3_bucket_public_access_block.frontend_static
  ]
}
