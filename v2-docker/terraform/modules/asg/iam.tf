# ──────────────────────────────────────────────
# IAM Role + Instance Profile
# ──────────────────────────────────────────────

resource "aws_iam_role" "this" {
  name = "${var.environment}-tasteam-asg-${var.purpose}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.environment}-tasteam-asg-${var.purpose}-profile"
  role = aws_iam_role.this.name
}

# ──────────────────────────────────────────────
# ECR — 이미지 풀링
# ──────────────────────────────────────────────

resource "aws_iam_role_policy" "ecr" {
  name = "ecr-pull"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ]
      Resource = "*"
    }]
  })
}

# ──────────────────────────────────────────────
# SSM — 파라미터 읽기 (backend + monitoring 네임스페이스)
# ──────────────────────────────────────────────

resource "aws_iam_role_policy" "ssm" {
  name = "ssm-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParametersByPath",
        "ssm:GetParameters",
        "ssm:GetParameter"
      ]
      Resource = [
        "arn:aws:ssm:*:*:parameter/${var.environment}/tasteam/backend",
        "arn:aws:ssm:*:*:parameter/${var.environment}/tasteam/backend/*",
        "arn:aws:ssm:*:*:parameter/${var.environment}/tasteam/monitoring",
        "arn:aws:ssm:*:*:parameter/${var.environment}/tasteam/monitoring/*"
      ]
    }]
  })
}

# ──────────────────────────────────────────────
# S3 — CodeDeploy 아티팩트 다운로드
# ──────────────────────────────────────────────

resource "aws_iam_role_policy" "codedeploy_artifacts_s3" {
  name = "codedeploy-artifacts-s3-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::tasteam-v2-codedeploy-artifacts/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning"
        ]
        Resource = "arn:aws:s3:::tasteam-v2-codedeploy-artifacts"
      }
    ]
  })
}

# ──────────────────────────────────────────────
# CodeDeploy Agent — secure commands
# ──────────────────────────────────────────────

resource "aws_iam_role_policy" "codedeploy_commands_secure" {
  name = "codedeploy-commands-secure"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "codedeploy-commands-secure:GetDeploymentSpecification",
        "codedeploy-commands-secure:PollHostCommand",
        "codedeploy-commands-secure:PutHostCommandAcknowledgement",
        "codedeploy-commands-secure:PutHostCommandComplete"
      ]
      Resource = "*"
    }]
  })
}

# ──────────────────────────────────────────────
# KMS — SecureString 파라미터 복호화
# ──────────────────────────────────────────────

resource "aws_iam_role_policy" "kms" {
  name = "kms-decrypt"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = "*"
    }]
  })
}
