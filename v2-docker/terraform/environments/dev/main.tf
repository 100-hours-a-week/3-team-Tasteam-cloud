# ──────────────────────────────────────────────
# Network — VPC, Subnets, IGW, Route Tables
# ──────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  environment          = var.environment
  vpc_cidr             = "10.13.0.0/16"
  public_subnet_cidrs  = ["10.13.0.0/20", "10.13.16.0/20"]
  private_subnet_cidrs = ["10.13.128.0/20", "10.13.144.0/20"]
  availability_zones   = ["ap-northeast-2a", "ap-northeast-2c"]
}

# ──────────────────────────────────────────────
# Security Groups
# ──────────────────────────────────────────────

module "security" {
  source = "../../modules/security"

  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  shared_vpc_cidr = "10.10.0.0/16"
}

# ──────────────────────────────────────────────
# AMI — Docker Ubuntu
# ──────────────────────────────────────────────

data "aws_ami" "docker_base" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["shared-ami-docker-*"]
  }

  filter {
    name   = "tag:Version"
    values = ["v1.0"]
  }
}

# ──────────────────────────────────────────────
# EC2 — Caddy (Reverse Proxy)
# ──────────────────────────────────────────────

module "ec2_caddy" {
  source = "../../modules/ec2"

  environment                 = var.environment
  purpose                     = "caddy"
  instance_type               = "t3.micro"
  ami_id                      = data.aws_ami.docker_base.id
  subnet_id                   = module.vpc.public_subnet_ids[0]
  security_group_ids          = [module.security.app_sg_id]
  associate_public_ip_address = true
}

# ──────────────────────────────────────────────
# SSM Parameter Store
# ──────────────────────────────────────────────

module "ssm" {
  source = "../../modules/ssm"

  environment = var.environment

  parameters = {
    # ── Spring Boot: DB ──
    "backend/DB_URL"      = { type = "SecureString", description = "PostgreSQL JDBC URL" }
    "backend/DB_USERNAME" = { type = "SecureString", description = "DB username" }
    "backend/DB_PASSWORD" = { type = "SecureString", description = "DB password" }

    # ── Spring Boot: Redis ──
    "backend/REDIS_HOST" = { type = "String", description = "Redis host" }
    "backend/REDIS_PORT" = { type = "String", description = "Redis port" }

    # ── Spring Boot: JWT ──
    "backend/JWT_SECRET"                   = { type = "SecureString", description = "JWT signing secret" }
    "backend/JWT_ACCESS_TOKEN_EXPIRATION"  = { type = "String", description = "Access token TTL (ms)" }
    "backend/JWT_REFRESH_TOKEN_EXPIRATION" = { type = "String", description = "Refresh token TTL (ms)" }

    # ── Spring Boot: OAuth2 ──
    "backend/GOOGLE_CLIENT_ID"     = { type = "SecureString", description = "Google OAuth client ID" }
    "backend/GOOGLE_CLIENT_SECRET" = { type = "SecureString", description = "Google OAuth client secret" }
    "backend/KAKAO_CLIENT_ID"      = { type = "SecureString", description = "Kakao OAuth client ID" }
    "backend/KAKAO_CLIENT_SECRET"  = { type = "SecureString", description = "Kakao OAuth client secret" }

    # ── Spring Boot: Storage ──
    "backend/STORAGE_TYPE"                         = { type = "String", description = "Storage type (s3/dummy)" }
    "backend/STORAGE_REGION"                       = { type = "String", description = "S3 region" }
    "backend/STORAGE_BUCKET"                       = { type = "String", description = "S3 bucket name" }
    "backend/STORAGE_BASE_URL"                     = { type = "String", description = "S3 base URL" }
    "backend/STORAGE_PRESIGNED_EXPIRATION_SECONDS" = { type = "String", description = "Presigned URL TTL (seconds)" }
    "backend/STORAGE_TEMP_UPLOAD_PREFIX"           = { type = "String", description = "Temp upload key prefix" }

    # ── Spring Boot: CORS ──
    "backend/CORS_ALLOWED_ORIGINS" = { type = "String", description = "CORS allowed origins (comma-separated)" }
    "backend/CORS_ALLOWED_HEADERS" = { type = "String", description = "CORS allowed headers (comma-separated)" }
    "backend/CORS_EXPOSED_HEADERS" = { type = "String", description = "CORS exposed headers (comma-separated)" }
    "backend/CORS_ALLOWED_METHODS" = { type = "String", description = "CORS allowed methods (comma-separated)" }

    # ── Spring Boot: File cleanup ──
    "backend/FILE_CLEANUP_TTL_SECONDS"    = { type = "String", description = "File cleanup TTL (seconds)" }
    "backend/FILE_CLEANUP_FIXED_DELAY_MS" = { type = "String", description = "File cleanup fixed delay (ms)" }

    # ── Spring Boot: Naver Maps ──
    "backend/NAVER_MAPS_API_KEY_ID" = { type = "SecureString", description = "Naver Maps API key ID" }
    "backend/NAVER_MAPS_API_KEY"    = { type = "SecureString", description = "Naver Maps API key" }

    # ── Spring Boot: Webhook ──
    "backend/WEBHOOK_ENABLED"         = { type = "String", description = "Webhook enabled flag" }
    "backend/WEBHOOK_PROVIDER"        = { type = "String", description = "Webhook provider" }
    "backend/DISCORD_WEBHOOK_URL"     = { type = "SecureString", description = "Discord webhook URL" }
    "backend/WEBHOOK_RETRY_MAX"       = { type = "String", description = "Webhook retry max attempts" }
    "backend/WEBHOOK_RETRY_BACKOFF"   = { type = "String", description = "Webhook retry backoff (ms)" }
    "backend/WEBHOOK_MIN_HTTP_STATUS" = { type = "String", description = "Webhook minimum HTTP status to notify" }

    # ── Spring Boot: Admin ──
    "backend/ADMIN_USERNAME" = { type = "SecureString", description = "Admin username" }
    "backend/ADMIN_PASSWORD" = { type = "SecureString", description = "Admin password" }

    # ── Spring Boot: Flyway ──
    "backend/FLYWAY_USER"     = { type = "SecureString", description = "Flyway DB user" }
    "backend/FLYWAY_PASSWORD" = { type = "SecureString", description = "Flyway DB password" }

    # ── Spring Boot: Firebase ──
    "backend/FIREBASE_ENABLED"                = { type = "String", description = "Firebase enable flag" }
    "backend/FIREBASE_PROJECT_ID"             = { type = "String", description = "Firebase project ID" }
    "backend/FIREBASE_SERVICE_ACCOUNT_BASE64" = { type = "SecureString", description = "Firebase service account (base64)" }

    # ── Spring Boot: Logging ──
    "backend/LOG_FILE_PATH"     = { type = "String", description = "Log file path" }
    "backend/LOG_MAX_FILE_SIZE" = { type = "String", description = "Log max file size" }
    "backend/LOG_MAX_HISTORY"   = { type = "String", description = "Log max history" }

    # ── Frontend (Vite) ──
    "frontend/VITE_APP_ENV"                      = { type = "String", description = "Frontend app environment" }
    "frontend/VITE_APP_URL"                      = { type = "String", description = "Frontend app base URL" }
    "frontend/VITE_API_BASE_URL"                 = { type = "String", description = "Frontend API base URL" }
    "frontend/VITE_DUMMY_DATA"                   = { type = "String", description = "Frontend dummy data toggle" }
    "frontend/VITE_AUTH_DEBUG"                   = { type = "String", description = "Frontend auth debug toggle" }
    "frontend/VITE_LOG_LEVEL"                    = { type = "String", description = "Frontend log level" }
    "frontend/VITE_FIREBASE_API_KEY"             = { type = "String", description = "Firebase API key" }
    "frontend/VITE_FIREBASE_AUTH_DOMAIN"         = { type = "String", description = "Firebase auth domain" }
    "frontend/VITE_FIREBASE_PROJECT_ID"          = { type = "String", description = "Firebase project ID" }
    "frontend/VITE_FIREBASE_STORAGE_BUCKET"      = { type = "String", description = "Firebase storage bucket" }
    "frontend/VITE_FIREBASE_MESSAGING_SENDER_ID" = { type = "String", description = "Firebase messaging sender ID" }
    "frontend/VITE_FIREBASE_APP_ID"              = { type = "String", description = "Firebase app ID" }
    "frontend/VITE_FIREBASE_VAPID_KEY"           = { type = "String", description = "Firebase VAPID key" }

    # ── FastAPI ──
    "fastapi/openai-api-key" = { type = "SecureString", description = "OpenAI API key" }
    "fastapi/db-url"         = { type = "SecureString", description = "FastAPI DB connection URL" }

    # ── Monitoring ──
    "monitoring/grafana-admin-password" = { type = "SecureString", description = "Grafana admin password" }
  }
}

# ──────────────────────────────────────────────
# Security Group — Spring Boot 전용
# ──────────────────────────────────────────────

resource "aws_security_group" "spring" {
  description = "Security group for Spring Boot application server"
  name        = "${var.environment}-sg-spring"
  vpc_id      = module.vpc.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    description = "SSH"
  }

  ingress {
    security_groups = [module.security.app_sg_id]
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    description     = "Spring Boot from Caddy only"
  }

  tags = {
    Name = "${var.environment}-sg-spring"
  }
}

# ──────────────────────────────────────────────
# EC2 — Spring Boot Application
# ──────────────────────────────────────────────

module "ec2_spring" {
  source = "../../modules/ec2"

  environment                 = var.environment
  purpose                     = "spring"
  instance_type               = "t3.small"
  ami_id                      = "ami-00b6cd96f80a61923"
  subnet_id                   = module.vpc.private_subnet_ids[0]
  security_group_ids          = [aws_security_group.spring.id]
  associate_public_ip_address = false
  manage_key_pair             = true
  iam_instance_profile        = aws_iam_instance_profile.dev_backend_ec2.name
}

# ──────────────────────────────────────────────
# AMI — fck-nat
# ──────────────────────────────────────────────

data "aws_ami" "fck_nat" {
  most_recent = true
  owners      = ["568608671756"]

  filter {
    name   = "name"
    values = ["fck-nat-al2023-*-arm64-*"]
  }
}

# ──────────────────────────────────────────────
# NAT Instance
# ──────────────────────────────────────────────

module "nat" {
  source = "../../modules/nat"

  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  vpc_cidr               = module.vpc.vpc_cidr_block
  public_subnet_id       = module.vpc.public_subnet_ids[0]
  private_route_table_id = module.vpc.private_route_table_id
  ami_id                 = data.aws_ami.fck_nat.id
  instance_type          = "t4g.nano"
}

# ──────────────────────────────────────────────
# IAM — Dev Backend EC2 Instance Profile
# ──────────────────────────────────────────────

resource "aws_iam_role" "dev_backend_ec2" {
  name = "${var.environment}-backend-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "dev_backend_ec2" {
  name = "${var.environment}-backend-ec2-policy"
  role = aws_iam_role.dev_backend_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParametersByPath",
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        Resource = "*"
      },
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
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy-commands-secure:GetDeploymentSpecification",
          "codedeploy-commands-secure:PollHostCommand",
          "codedeploy-commands-secure:PutHostCommandAcknowledgement",
          "codedeploy-commands-secure:PutHostCommandComplete"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "dev_backend_ec2" {
  name = "${var.environment}-backend-ec2-instance-profile"
  role = aws_iam_role.dev_backend_ec2.name
}

# ──────────────────────────────────────────────
# CodeDeploy — Backend (Dev)
# ──────────────────────────────────────────────

resource "aws_iam_role" "codedeploy_service" {
  name = "${var.environment}-codedeploy-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codedeploy.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_service" {
  role       = aws_iam_role.codedeploy_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

resource "aws_codedeploy_app" "backend" {
  compute_platform = "Server"
  name             = var.codedeploy_app_name
}

resource "aws_codedeploy_deployment_group" "backend_dev" {
  app_name              = aws_codedeploy_app.backend.name
  deployment_group_name = var.codedeploy_deployment_group_name
  service_role_arn      = aws_iam_role.codedeploy_service.arn

  deployment_config_name = "CodeDeployDefault.OneAtATime"

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Name"
      type  = "KEY_AND_VALUE"
      value = "${var.environment}-ec2-spring"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.codedeploy_service
  ]
}
