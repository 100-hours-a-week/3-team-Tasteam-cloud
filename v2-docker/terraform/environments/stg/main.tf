# ──────────────────────────────────────────────
# Network — VPC, Subnets, IGW, Route Tables
# ──────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  environment          = var.environment
  vpc_cidr             = "10.12.0.0/16"
  public_subnet_cidrs  = ["10.12.0.0/20", "10.12.16.0/20"]
  private_subnet_cidrs = ["10.12.128.0/20", "10.12.144.0/20"]
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
