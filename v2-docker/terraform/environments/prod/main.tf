# ──────────────────────────────────────────────
# Network — VPC, Subnets, IGW, Route Tables
# ──────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  environment          = var.environment
  vpc_cidr             = "10.11.0.0/16"
  public_subnet_cidrs  = ["10.11.0.0/20", "10.11.16.0/20"]
  private_subnet_cidrs = ["10.11.128.0/20", "10.11.144.0/20"]
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
# SSM Parameter Store
# ──────────────────────────────────────────────

module "ssm" {
  source = "../../modules/ssm"

  environment = var.environment

  parameters = {
    # ── Spring Boot: DB ──
    "backend/DB_URL" = { type = "SecureString", description = "PostgreSQL JDBC URL" }
    "backend/DB_USERNAME" = { type = "SecureString", description = "DB username" }
    "backend/DB_PASSWORD" = { type = "SecureString", description = "DB password" }

    # ── Spring Boot: Redis ──
    "backend/REDIS_HOST" = { type = "String", description = "Redis host" }
    "backend/REDIS_PORT" = { type = "String", description = "Redis port" }

    # ── Spring Boot: JWT ──
    "backend/JWT_SECRET" = { type = "SecureString", description = "JWT signing secret" }
    "backend/JWT_ACCESS_TOKEN_EXPIRATION" = { type = "String", description = "Access token TTL (ms)" }
    "backend/JWT_REFRESH_TOKEN_EXPIRATION" = { type = "String", description = "Refresh token TTL (ms)" }

    # ── Spring Boot: OAuth2 ──
    "backend/GOOGLE_CLIENT_ID" = { type = "SecureString", description = "Google OAuth client ID" }
    "backend/GOOGLE_CLIENT_SECRET" = { type = "SecureString", description = "Google OAuth client secret" }
    "backend/KAKAO_CLIENT_ID" = { type = "SecureString", description = "Kakao OAuth client ID" }
    "backend/KAKAO_CLIENT_SECRET" = { type = "SecureString", description = "Kakao OAuth client secret" }

    # ── Spring Boot: Storage ──
    "backend/STORAGE_TYPE" = { type = "String", description = "Storage type (s3/dummy)" }
    "backend/STORAGE_REGION" = { type = "String", description = "S3 region" }
    "backend/STORAGE_BUCKET" = { type = "String", description = "S3 bucket name" }
    "backend/STORAGE_BASE_URL" = { type = "String", description = "S3 base URL" }
    "backend/STORAGE_PRESIGNED_EXPIRATION_SECONDS" = { type = "String", description = "Presigned URL TTL (seconds)" }
    "backend/STORAGE_TEMP_UPLOAD_PREFIX" = { type = "String", description = "Temp upload key prefix" }

    # ── Spring Boot: CORS ──
    "backend/CORS_ALLOWED_ORIGINS" = { type = "String", description = "CORS allowed origins (comma-separated)" }
    "backend/CORS_ALLOWED_HEADERS" = { type = "String", description = "CORS allowed headers (comma-separated)" }
    "backend/CORS_EXPOSED_HEADERS" = { type = "String", description = "CORS exposed headers (comma-separated)" }
    "backend/CORS_ALLOWED_METHODS" = { type = "String", description = "CORS allowed methods (comma-separated)" }

    # ── Spring Boot: File cleanup ──
    "backend/FILE_CLEANUP_TTL_SECONDS" = { type = "String", description = "File cleanup TTL (seconds)" }
    "backend/FILE_CLEANUP_FIXED_DELAY_MS" = { type = "String", description = "File cleanup fixed delay (ms)" }

    # ── Spring Boot: Naver Maps ──
    "backend/NAVER_MAPS_API_KEY_ID" = { type = "SecureString", description = "Naver Maps API key ID" }
    "backend/NAVER_MAPS_API_KEY" = { type = "SecureString", description = "Naver Maps API key" }

    # ── Spring Boot: Webhook ──
    "backend/WEBHOOK_ENABLED" = { type = "String", description = "Webhook enabled flag" }
    "backend/WEBHOOK_PROVIDER" = { type = "String", description = "Webhook provider" }
    "backend/DISCORD_WEBHOOK_URL" = { type = "SecureString", description = "Discord webhook URL" }
    "backend/WEBHOOK_RETRY_MAX" = { type = "String", description = "Webhook retry max attempts" }
    "backend/WEBHOOK_RETRY_BACKOFF" = { type = "String", description = "Webhook retry backoff (ms)" }
    "backend/WEBHOOK_MIN_HTTP_STATUS" = { type = "String", description = "Webhook minimum HTTP status to notify" }

    # ── Spring Boot: Admin ──
    "backend/ADMIN_USERNAME" = { type = "SecureString", description = "Admin username" }
    "backend/ADMIN_PASSWORD" = { type = "SecureString", description = "Admin password" }

    # ── Spring Boot: Flyway ──
    "backend/FLYWAY_USER" = { type = "SecureString", description = "Flyway DB user" }
    "backend/FLYWAY_PASSWORD" = { type = "SecureString", description = "Flyway DB password" }

    # ── Spring Boot: Firebase ──
    "backend/FIREBASE_ENABLED" = { type = "String", description = "Firebase enable flag" }
    "backend/FIREBASE_PROJECT_ID" = { type = "String", description = "Firebase project ID" }
    "backend/FIREBASE_SERVICE_ACCOUNT_BASE64" = { type = "SecureString", description = "Firebase service account (base64)" }

    # ── Spring Boot: Logging ──
    "backend/LOG_FILE_PATH" = { type = "String", description = "Log file path" }
    "backend/LOG_MAX_FILE_SIZE" = { type = "String", description = "Log max file size" }
    "backend/LOG_MAX_HISTORY" = { type = "String", description = "Log max history" }

    # ── Frontend (Vite) ──
    "frontend/VITE_APP_ENV"                  = { type = "String", description = "Frontend app environment" }
    "frontend/VITE_APP_URL"                  = { type = "String", description = "Frontend app base URL" }
    "frontend/VITE_API_BASE_URL"             = { type = "String", description = "Frontend API base URL" }
    "frontend/VITE_DUMMY_DATA"               = { type = "String", description = "Frontend dummy data toggle" }
    "frontend/VITE_AUTH_DEBUG"               = { type = "String", description = "Frontend auth debug toggle" }
    "frontend/VITE_LOG_LEVEL"                = { type = "String", description = "Frontend log level" }
    "frontend/VITE_FIREBASE_API_KEY"         = { type = "String", description = "Firebase API key" }
    "frontend/VITE_FIREBASE_AUTH_DOMAIN"     = { type = "String", description = "Firebase auth domain" }
    "frontend/VITE_FIREBASE_PROJECT_ID"      = { type = "String", description = "Firebase project ID" }
    "frontend/VITE_FIREBASE_STORAGE_BUCKET"  = { type = "String", description = "Firebase storage bucket" }
    "frontend/VITE_FIREBASE_MESSAGING_SENDER_ID" = { type = "String", description = "Firebase messaging sender ID" }
    "frontend/VITE_FIREBASE_APP_ID"          = { type = "String", description = "Firebase app ID" }
    "frontend/VITE_FIREBASE_VAPID_KEY"       = { type = "String", description = "Firebase VAPID key" }

    # ── FastAPI ──
    "fastapi/openai-api-key" = { type = "SecureString", description = "OpenAI API key" }
    "fastapi/db-url"         = { type = "SecureString", description = "FastAPI DB connection URL" }

    # ── Monitoring ──
    "monitoring/grafana-admin-password" = { type = "SecureString", description = "Grafana admin password" }
  }
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
# NAT Instance — Private Subnet 외부 통신
# ──────────────────────────────────────────────

module "nat" {
  source = "../../modules/nat"

  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  vpc_cidr               = module.vpc.vpc_cidr_block
  public_subnet_id       = module.vpc.public_subnet_ids[0]
  private_route_table_id = module.vpc.private_route_table_id
  ami_id                 = data.aws_ami.fck_nat.id
  instance_type          = "t4g.micro"
}

# ──────────────────────────────────────────────
# VPC Endpoint — S3 Gateway
# ECR 이미지 레이어(S3 저장)를 NAT 경유 없이 직접 접근
# ──────────────────────────────────────────────

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [module.vpc.private_route_table_id]

  tags = {
    Name = "${var.environment}-vpce-s3"
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
  manage_key_pair             = true
}

# ──────────────────────────────────────────────
# ASG — Spring Boot Backend
# ──────────────────────────────────────────────

module "asg_spring" {
  source = "../../modules/asg"

  environment        = var.environment
  purpose            = "spring"
  instance_type      = "t3.small"
  ami_id             = data.aws_ami.docker_base.id
  subnet_ids         = [module.vpc.private_subnet_ids[0]]
  security_group_ids = [module.security.app_sg_id]
  aws_region         = var.aws_region

  min_size     = 1
  desired_size = 1
  max_size     = 2

  app_port = 8080

  # 서비스 디스커버리 활성화
  enable_lifecycle_hooks = true
}

# ──────────────────────────────────────────────
# Cloud Map — 내부 서비스 디스커버리 네임스페이스
# ──────────────────────────────────────────────

module "cloud_map" {
  source = "../../modules/cloud-map"

  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  service_name = "spring"
}

# ──────────────────────────────────────────────
# Lambda — 서비스 디스커버리 (ASG lifecycle → Cloud Map)
# ──────────────────────────────────────────────

module "lambda_sd_spring" {
  source = "../../modules/lambda-sd"

  environment          = var.environment
  purpose              = "spring"
  asg_name             = module.asg_spring.asg_name
  cloud_map_service_id = module.cloud_map.service_id
  app_port             = 8080
}

# ──────────────────────────────────────────────
# Data Sources for V1 (Legacy)
# ──────────────────────────────────────────────

data "aws_caller_identity" "v1" {
  provider = aws.v1
}

data "aws_vpc" "v1" {
  provider = aws.v1
  filter {
    name   = "tag:Name"
    values = ["prod-vpc"]
  }
}

data "aws_route_table" "v1" {
  provider = aws.v1
  vpc_id   = data.aws_vpc.v1.id
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

# ──────────────────────────────────────────────
# VPC Peering with V1 (Legacy)
# ──────────────────────────────────────────────

# 1. Peering Request (From V2)
resource "aws_vpc_peering_connection" "v1_peering" {
  vpc_id        = module.vpc.vpc_id
  peer_vpc_id   = data.aws_vpc.v1.id
  peer_owner_id = data.aws_caller_identity.v1.account_id
  peer_region   = var.aws_region
  auto_accept   = false

  tags = {
    Name = "prod-pcx-v1"
    Side = "Requester"
  }
}

# 2. Peering Accepter (In V1)
resource "aws_vpc_peering_connection_accepter" "v1_peering_accepter" {
  provider                  = aws.v1
  vpc_peering_connection_id = aws_vpc_peering_connection.v1_peering.id
  auto_accept               = true

  tags = {
    Name = "prod-pcx-v1"
    Side = "Accepter"
  }
}

# 3. Routes: V2 -> V1
resource "aws_route" "to_v1" {
  route_table_id            = module.vpc.private_route_table_id
  destination_cidr_block    = data.aws_vpc.v1.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.v1_peering.id
}

# 4. Routes: V1 -> V2
resource "aws_route" "v1_to_prod" {
  provider                  = aws.v1
  route_table_id            = data.aws_route_table.v1.id
  destination_cidr_block    = module.vpc.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.v1_peering.id
}
