data "aws_caller_identity" "current" {}

locals {
  k8s_backup_bucket_name = "tasteam-${var.environment}-k8s-backup-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "k8s_backup" {
  bucket = local.k8s_backup_bucket_name

  tags = {
    Name    = "${var.environment}-k8s-backup"
    Purpose = "k8s-backup"
  }
}

resource "aws_s3_bucket_public_access_block" "k8s_backup" {
  bucket = aws_s3_bucket.k8s_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "k8s_backup" {
  bucket = aws_s3_bucket.k8s_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "k8s_backup" {
  bucket = aws_s3_bucket.k8s_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}
