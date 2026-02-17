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
