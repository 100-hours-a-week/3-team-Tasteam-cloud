# Development 환경용 S3 버킷
resource "aws_s3_bucket" "uploads" {
  bucket = "tasteam-uploads-development"

  tags = {
    Name        = "tasteam-uploads-development"
    Purpose     = "presigned-url-uploads"
    Environment = var.environment
  }
}

# 퍼블릭 액세스 차단 (Presigned URL만 허용)
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CORS 설정 (프론트엔드에서 직접 업로드 허용)
resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"] # 프로덕션에서는 특정 도메인으로 제한 권장
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# 버킷 암호화 (보안 강화)
resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
