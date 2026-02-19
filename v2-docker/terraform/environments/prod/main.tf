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
    "spring/db-url"      = { type = "SecureString", description = "PostgreSQL JDBC URL" }
    "spring/db-username" = { type = "SecureString", description = "DB username" }
    "spring/db-password" = { type = "SecureString", description = "DB password" }

    # ── Spring Boot: Redis ──
    "spring/redis-host" = { type = "String", description = "Redis host" }
    "spring/redis-port" = { type = "String", description = "Redis port" }

    # ── Spring Boot: JWT ──
    "spring/jwt-secret"                   = { type = "SecureString", description = "JWT signing secret" }
    "spring/jwt-access-token-expiration"  = { type = "String", description = "Access token TTL (ms)" }
    "spring/jwt-refresh-token-expiration" = { type = "String", description = "Refresh token TTL (ms)" }

    # ── Spring Boot: OAuth2 ──
    "spring/google-client-id"     = { type = "SecureString", description = "Google OAuth client ID" }
    "spring/google-client-secret" = { type = "SecureString", description = "Google OAuth client secret" }
    "spring/kakao-client-id"      = { type = "SecureString", description = "Kakao OAuth client ID" }
    "spring/kakao-client-secret"  = { type = "SecureString", description = "Kakao OAuth client secret" }

    # ── Spring Boot: CORS ──
    "spring/cors-allowed-origins" = { type = "String", description = "CORS allowed origins (comma-separated)" }

    # ── Spring Boot: S3 Storage ──
    "spring/storage-region"     = { type = "String", description = "S3 region" }
    "spring/storage-bucket"     = { type = "String", description = "S3 bucket name" }
    "spring/storage-base-url"   = { type = "String", description = "S3 base URL" }
    "spring/storage-access-key" = { type = "SecureString", description = "S3 access key" }
    "spring/storage-secret-key" = { type = "SecureString", description = "S3 secret key" }

    # ── Spring Boot: Naver Maps ──
    "spring/naver-maps-api-key-id" = { type = "SecureString", description = "Naver Maps API key ID" }
    "spring/naver-maps-api-key"    = { type = "SecureString", description = "Naver Maps API key" }

    # ── Spring Boot: Domain ──
    "spring/service-domain" = { type = "String", description = "Service domain (e.g. https://tasteam.kr)" }
    "spring/api-domain"     = { type = "String", description = "API domain (e.g. https://api.tasteam.kr)" }

    # ── Spring Boot: Admin ──
    "spring/admin-username" = { type = "SecureString", description = "Admin username" }
    "spring/admin-password" = { type = "SecureString", description = "Admin password" }

    # ── Spring Boot: Webhook ──
    "spring/discord-webhook-url" = { type = "SecureString", description = "Discord webhook URL" }

    # ── Spring Boot: Firebase ──
    "spring/firebase-project-id"             = { type = "String", description = "Firebase project ID" }
    "spring/firebase-service-account-base64" = { type = "SecureString", description = "Firebase service account (base64)" }

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
  key_name                    = var.key_name
  associate_public_ip_address = true
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
