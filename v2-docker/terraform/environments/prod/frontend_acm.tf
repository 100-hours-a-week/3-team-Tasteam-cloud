# ──────────────────────────────────────────────
# Frontend CDN — ACM Certificate (us-east-1)
# CloudFront custom domain certificate must live in us-east-1.
# DNS validation records are exposed via outputs for Cloudflare 등록.
# ──────────────────────────────────────────────

resource "aws_acm_certificate" "frontend_cloudfront" {
  provider = aws.us_east_1

  domain_name               = var.frontend_certificate_domain_name
  subject_alternative_names = var.frontend_certificate_san_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name    = "${var.environment}-frontend-cloudfront-cert"
    Purpose = "frontend-cdn-custom-domain"
  }
}
