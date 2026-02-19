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

  environment = var.environment
  vpc_id      = module.vpc.vpc_id
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
    "DB_URL"      = { type = "SecureString", description = "PostgreSQL JDBC URL" }
    "DB_USERNAME" = { type = "SecureString", description = "DB username" }
    "DB_PASSWORD" = { type = "SecureString", description = "DB password" }

    # ── Spring Boot: Redis ──
    "REDIS_HOST" = { type = "String", description = "Redis host" }
    "REDIS_PORT" = { type = "String", description = "Redis port" }

    # ── Spring Boot: JWT ──
    "JWT_SECRET"                   = { type = "SecureString", description = "JWT signing secret" }
    "JWT_ACCESS_TOKEN_EXPIRATION"  = { type = "String", description = "Access token TTL (ms)" }
    "JWT_REFRESH_TOKEN_EXPIRATION" = { type = "String", description = "Refresh token TTL (ms)" }

    # ── Spring Boot: OAuth2 ──
    "GOOGLE_CLIENT_ID"     = { type = "SecureString", description = "Google OAuth client ID" }
    "GOOGLE_CLIENT_SECRET" = { type = "SecureString", description = "Google OAuth client secret" }
    "KAKAO_CLIENT_ID"      = { type = "SecureString", description = "Kakao OAuth client ID" }
    "KAKAO_CLIENT_SECRET"  = { type = "SecureString", description = "Kakao OAuth client secret" }

    # ── Spring Boot: Storage ──
    "STORAGE_TYPE"                         = { type = "String", description = "Storage type (s3/dummy)" }
    "STORAGE_REGION"                       = { type = "String", description = "S3 region" }
    "STORAGE_BUCKET"                       = { type = "String", description = "S3 bucket name" }
    "STORAGE_BASE_URL"                     = { type = "String", description = "S3 base URL" }
    "STORAGE_PRESIGNED_EXPIRATION_SECONDS" = { type = "String", description = "Presigned URL TTL (seconds)" }
    "STORAGE_TEMP_UPLOAD_PREFIX"           = { type = "String", description = "Temp upload key prefix" }

    # ── Spring Boot: CORS ──
    "CORS_ALLOWED_ORIGINS" = { type = "String", description = "CORS allowed origins (comma-separated)" }
    "CORS_ALLOWED_HEADERS" = { type = "String", description = "CORS allowed headers (comma-separated)" }
    "CORS_EXPOSED_HEADERS" = { type = "String", description = "CORS exposed headers (comma-separated)" }
    "CORS_ALLOWED_METHODS" = { type = "String", description = "CORS allowed methods (comma-separated)" }

    # ── Spring Boot: File cleanup ──
    "FILE_CLEANUP_TTL_SECONDS" = { type = "String", description = "File cleanup TTL (seconds)" }
    "FILE_CLEANUP_FIXED_DELAY_MS" = { type = "String", description = "File cleanup fixed delay (ms)" }

    # ── Spring Boot: Naver Maps ──
    "NAVER_MAPS_API_KEY_ID" = { type = "SecureString", description = "Naver Maps API key ID" }
    "NAVER_MAPS_API_KEY"    = { type = "SecureString", description = "Naver Maps API key" }

    # ── Spring Boot: Webhook ──
    "WEBHOOK_ENABLED"          = { type = "String", description = "Webhook enabled flag" }
    "WEBHOOK_PROVIDER"         = { type = "String", description = "Webhook provider" }
    "DISCORD_WEBHOOK_URL"      = { type = "SecureString", description = "Discord webhook URL" }
    "WEBHOOK_RETRY_MAX"        = { type = "String", description = "Webhook retry max attempts" }
    "WEBHOOK_RETRY_BACKOFF"    = { type = "String", description = "Webhook retry backoff (ms)" }
    "WEBHOOK_MIN_HTTP_STATUS"  = { type = "String", description = "Webhook minimum HTTP status to notify" }

    # ── Spring Boot: Admin ──
    "ADMIN_USERNAME" = { type = "SecureString", description = "Admin username" }
    "ADMIN_PASSWORD" = { type = "SecureString", description = "Admin password" }

    # ── Spring Boot: Flyway ──
    "FLYWAY_USER"     = { type = "SecureString", description = "Flyway DB user" }
    "FLYWAY_PASSWORD" = { type = "SecureString", description = "Flyway DB password" }

    # ── Spring Boot: Firebase ──
    "FIREBASE_ENABLED"                = { type = "String", description = "Firebase enable flag" }
    "FIREBASE_PROJECT_ID"             = { type = "String", description = "Firebase project ID" }
    "FIREBASE_SERVICE_ACCOUNT_BASE64" = { type = "SecureString", description = "Firebase service account (base64)" }

    # ── Spring Boot: Logging ──
    "LOG_FILE_PATH"     = { type = "String", description = "Log file path" }
    "LOG_MAX_FILE_SIZE" = { type = "String", description = "Log max file size" }
    "LOG_MAX_HISTORY"   = { type = "String", description = "Log max history" }

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

  environment        = var.environment
  purpose            = "spring"
  instance_type      = "t3.small"
  ami_id             = data.aws_ami.docker_base.id
  subnet_id          = module.vpc.private_subnet_ids[0]
  security_group_ids          = [aws_security_group.spring.id]
  associate_public_ip_address = false
  manage_key_pair             = true
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
