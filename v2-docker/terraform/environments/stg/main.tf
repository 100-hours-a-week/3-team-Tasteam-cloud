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

  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  shared_vpc_cidr = "10.10.0.0/16"
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
