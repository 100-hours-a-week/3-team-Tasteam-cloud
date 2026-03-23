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

  environment                       = var.environment
  vpc_id                            = module.vpc.vpc_id
  shared_vpc_cidr                   = "10.10.0.0/16"
  app_ssh_cidr_blocks               = var.caddy_admin_ssh_cidrs
  app_ssh_source_security_group_ids = [aws_security_group.caddy_jump_source.id]
}

# ──────────────────────────────────────────────
# Security Groups — Source Markers (Redis/Kafka 접근 제어용)
# 기존 app_sg를 Caddy/ASG가 함께 사용하므로, 서비스 SG에서는
# source 전용 SG를 별도 부착해 더 좁게 제어한다.
# ──────────────────────────────────────────────

resource "aws_security_group" "caddy_jump_source" {
  name        = "${var.environment}-sg-caddy-jump-source"
  description = "Marker SG attached to caddy EC2 for Redis SSH source restriction"
  vpc_id      = module.vpc.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  tags = {
    Name = "${var.environment}-sg-caddy-jump-source"
  }
}

resource "aws_security_group" "spring_redis_source" {
  name        = "${var.environment}-sg-spring-redis-source"
  description = "Marker SG attached to Spring ASG instances for Redis 6379 access"
  vpc_id      = module.vpc.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  tags = {
    Name = "${var.environment}-sg-spring-redis-source"
  }
}

resource "aws_security_group" "spring_kafka_source" {
  name        = "${var.environment}-sg-spring-kafka-source"
  description = "Marker SG attached to Spring ASG instances for Kafka 9092 access"
  vpc_id      = module.vpc.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  tags = {
    Name = "${var.environment}-sg-spring-kafka-source"
  }
}

# ──────────────────────────────────────────────
# SSM Parameter Store
# ──────────────────────────────────────────────

module "ssm" {
  source = "../../modules/ssm"

  environment = var.environment

  parameters = {
    # ── Spring Boot: DB ──
    # 참고: DB_URL은 이 파일 하단(RDS 모듈 부근)의 aws_ssm_parameter 리소스로
    # 동적으로 생성/관리합니다. DB_USERNAME, DB_PASSWORD는 수동 입력값(SSM)입니다.
    "backend/DB_USERNAME" = { type = "SecureString", description = "DB username" }
    "backend/DB_PASSWORD" = { type = "SecureString", description = "DB password" }

    # ── Spring Boot: Redis ──
    # 참고: REDIS_HOST, REDIS_PORT는 Redis EC2 생성 이후 이 파일 하단의
    # aws_ssm_parameter 리소스에서 동적으로 생성/관리합니다.

    # ── Spring Boot: Kafka ──
    # 참고: KAFKA_BOOTSTRAP_SERVERS는 Kafka EC2 생성 이후 이 파일 하단의
    # aws_ssm_parameter 리소스에서 동적으로 생성/관리합니다.

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
    "fastapi/OPENAI_API_KEY"         = { type = "SecureString", description = "OpenAI API key" }
    "fastapi/GEMINI_API_KEY"         = { type = "SecureString", description = "Gemini API key" }
    "fastapi/WANDB_API_KEY"          = { type = "SecureString", description = "Weights & Biases API key" }
    "fastapi/RUNPOD_API_KEY"         = { type = "SecureString", description = "RunPod API key" }
    "fastapi/QDRANT_VECTORS_ON_DISK" = { type = "String", description = "Qdrant vectors on disk toggle" }
    # 참고: QDRANT_URL은 Qdrant EC2 생성 이후 이 파일 하단의
    # aws_ssm_parameter 리소스에서 동적으로 생성/관리합니다.
    "fastapi/HF_HOME"             = { type = "String", description = "Hugging Face cache home directory" }
    "fastapi/EMBEDDING_CACHE_DIR" = { type = "String", description = "Embedding cache directory" }
    "fastapi/DB_URL"              = { type = "SecureString", description = "FastAPI DB connection URL" }

    # ── Monitoring ──
    "monitoring/GRAFANA_ADMIN_PASSWORD" = { type = "SecureString", description = "Grafana admin password" }
    "monitoring/LOKI_HOST"              = { type = "String", description = "Loki host (shared monitoring EC2)" }
    "monitoring/PROMETHEUS_HOST"        = { type = "String", description = "Prometheus host (shared monitoring EC2)" }
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
# S3 — Application Upload Bucket
# ──────────────────────────────────────────────

resource "aws_s3_bucket" "uploads" {
  bucket = var.upload_bucket_name

  tags = {
    Name    = "${var.environment}-uploads"
    Purpose = "application-uploads"
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ──────────────────────────────────────────────
# S3 — Frontend Static Bucket (private)
# ──────────────────────────────────────────────

resource "aws_s3_bucket" "frontend_static" {
  bucket = var.frontend_static_bucket_name

  tags = {
    Name    = "${var.environment}-frontend-static"
    Purpose = "frontend-static-hosting"
  }
}

resource "aws_s3_bucket_ownership_controls" "frontend_static" {
  bucket = aws_s3_bucket.frontend_static.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_static" {
  bucket = aws_s3_bucket.frontend_static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend_static" {
  bucket = aws_s3_bucket.frontend_static.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ──────────────────────────────────────────────
# S3 — Application Analytics Bucket
# ──────────────────────────────────────────────

resource "aws_s3_bucket" "analytics" {
  bucket = "tasteam-${var.environment}-analytics"

  tags = {
    Name    = "${var.environment}-analytics"
    Purpose = "application-analytics"
  }
}

resource "aws_s3_bucket_public_access_block" "analytics" {
  bucket = aws_s3_bucket.analytics.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "analytics" {
  bucket = aws_s3_bucket.analytics.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "analytics" {
  bucket = aws_s3_bucket.analytics.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "uploads_v1_migration" {
  count = length(var.v1_migration_principal_arns) > 0 ? 1 : 0

  statement {
    sid = "AllowV1MigrationBucketList"

    principals {
      type        = "AWS"
      identifiers = var.v1_migration_principal_arns
    }

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]

    resources = [aws_s3_bucket.uploads.arn]
  }

  statement {
    sid = "AllowV1MigrationObjectAccess"

    principals {
      type        = "AWS"
      identifiers = var.v1_migration_principal_arns
    }

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:PutObjectTagging",
      "s3:GetObjectTagging",
    ]

    resources = ["${aws_s3_bucket.uploads.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "uploads_v1_migration" {
  count = length(var.v1_migration_principal_arns) > 0 ? 1 : 0

  bucket = aws_s3_bucket.uploads.id
  policy = data.aws_iam_policy_document.uploads_v1_migration[0].json
}

# ──────────────────────────────────────────────
# EC2 — Caddy (Reverse Proxy)
# ──────────────────────────────────────────────

module "ec2_caddy" {
  source = "../../modules/ec2"

  environment                 = var.environment
  purpose                     = "caddy"
  instance_type               = "t3.micro"
  ami_id                      = "ami-06a52e8f1f5ac0587"
  subnet_id                   = module.vpc.public_subnet_ids[0]
  security_group_ids          = [module.security.app_sg_id, aws_security_group.caddy_jump_source.id]
  associate_public_ip_address = true
  assign_eip                  = true
  manage_key_pair             = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_common.name
}

# ──────────────────────────────────────────────
# ASG — Spring Boot Backend
# ──────────────────────────────────────────────

module "asg_spring" {
  source = "../../modules/asg"

  environment   = var.environment
  purpose       = "spring"
  instance_type = "t3.small"
  ami_id        = "ami-05c852fd45180f54f"
  subnet_ids    = [module.vpc.private_subnet_ids[0]]
  security_group_ids = [
    module.security.app_sg_id,
    aws_security_group.spring_redis_source.id,
    aws_security_group.spring_kafka_source.id,
  ]
  aws_region = var.aws_region

  min_size     = 1
  desired_size = 1
  max_size     = 2

  app_port = 8080

  enable_lifecycle_hooks = true
  manage_key_pair        = true
}

# ──────────────────────────────────────────────
# Security Group — Redis (Private)
# - 6379: Spring ASG 인스턴스만 허용
# - 22: Caddy 점프호스트만 허용
# ──────────────────────────────────────────────

resource "aws_security_group" "redis_private" {
  description = "Security group for staging Redis EC2 (private subnet)"
  name        = "${var.environment}-sg-redis-private"
  vpc_id      = module.vpc.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  ingress {
    security_groups = [aws_security_group.spring_redis_source.id]
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    description     = "Redis from Spring ASG instances only"
  }

  ingress {
    security_groups = [module.security.app_sg_id]
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    description     = "Temporary Redis access from shared app_sg during ASG rollout"
  }

  ingress {
    security_groups = [aws_security_group.caddy_jump_source.id]
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    description     = "SSH from Caddy jump host only"
  }

  tags = {
    Name = "${var.environment}-sg-redis-private"
  }
}

# ──────────────────────────────────────────────
# EC2 — Redis (Private)
# - Private subnet 배치
# - Public IP/EIP 미사용
# - SSH는 Caddy 점프호스트 경유
# ──────────────────────────────────────────────

module "ec2_redis" {
  source = "../../modules/ec2"

  environment                 = var.environment
  purpose                     = "redis"
  instance_type               = "t3.small"
  ami_id                      = data.aws_ami.docker_base.id
  subnet_id                   = module.vpc.private_subnet_ids[0]
  security_group_ids          = [aws_security_group.redis_private.id]
  associate_public_ip_address = false
  manage_key_pair             = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_common.name
}

# ──────────────────────────────────────────────
# Security Group — Qdrant (Private)
# - 6333: FastAPI → Qdrant (HTTP REST)
# - 6334: FastAPI → Qdrant (gRPC)
# - 22: Caddy 점프호스트만 허용
# ──────────────────────────────────────────────

resource "aws_security_group" "qdrant_private" {
  description = "Security group for staging Qdrant EC2 (private subnet)"
  name        = "${var.environment}-sg-qdrant-private"
  vpc_id      = module.vpc.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  ingress {
    security_groups = [module.security.app_sg_id]
    from_port       = 6333
    to_port         = 6333
    protocol        = "tcp"
    description     = "Qdrant HTTP from app SG (FastAPI)"
  }

  ingress {
    security_groups = [module.security.app_sg_id]
    from_port       = 6334
    to_port         = 6334
    protocol        = "tcp"
    description     = "Qdrant gRPC from app SG (FastAPI)"
  }

  ingress {
    security_groups = [aws_security_group.caddy_jump_source.id]
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    description     = "SSH from Caddy jump host only"
  }

  tags = {
    Name = "${var.environment}-sg-qdrant-private"
  }
}

# ──────────────────────────────────────────────
# EC2 — Qdrant (Private)
# - Private subnet 배치
# - Public IP/EIP 미사용
# - SSH는 Caddy 점프호스트 경유
# ──────────────────────────────────────────────

module "ec2_qdrant" {
  source = "../../modules/ec2"

  environment                 = var.environment
  purpose                     = "qdrant"
  instance_type               = "t3.small"
  ami_id                      = data.aws_ami.docker_base.id
  subnet_id                   = module.vpc.private_subnet_ids[0]
  security_group_ids          = [aws_security_group.qdrant_private.id]
  associate_public_ip_address = false
  manage_key_pair             = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_common.name
}

# ──────────────────────────────────────────────
# Security Group — Kafka (Private)
# - 9092, 29092: Spring ASG 인스턴스 허용
# - 9092~9093, 29092: Kafka 브로커 간 통신(self)
# - 22: Caddy 점프호스트만 허용
# ──────────────────────────────────────────────

resource "aws_security_group" "kafka_private" {
  description = "Security group for staging Kafka EC2 (private subnet)"
  name        = "${var.environment}-sg-kafka-private"
  vpc_id      = module.vpc.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  ingress {
    security_groups = [aws_security_group.spring_kafka_source.id]
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    description     = "Kafka client traffic from Spring ASG instances only"
  }

  ingress {
    security_groups = [aws_security_group.spring_kafka_source.id]
    from_port       = 29092
    to_port         = 29092
    protocol        = "tcp"
    description     = "Kafka external listener from Spring ASG instances"
  }

  ingress {
    security_groups = [module.security.app_sg_id]
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    description     = "Temporary Kafka access from shared app_sg during ASG rollout"
  }

  # Prod K8s 워커 → Stg Kafka (VPC 피어링 경유)
  ingress {
    cidr_blocks = ["10.11.0.0/16"]
    from_port   = 29092
    to_port     = 29092
    protocol    = "tcp"
    description = "Kafka external listener from prod K8s workers via VPC peering"
  }

  ingress {
    self        = true
    from_port   = 9092
    to_port     = 9093
    protocol    = "tcp"
    description = "Kafka inter-broker/controller communication"
  }

  ingress {
    self        = true
    from_port   = 29092
    to_port     = 29092
    protocol    = "tcp"
    description = "Kafka inter-broker external listener communication"
  }

  ingress {
    security_groups = [aws_security_group.caddy_jump_source.id]
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    description     = "SSH from Caddy jump host only"
  }

  ingress {
    cidr_blocks = ["10.10.0.0/16"]
    from_port   = 7071
    to_port     = 7072
    protocol    = "tcp"
    description = "Kafka JMX exporter (broker/connect) from monitoring server"
  }

  ingress {
    cidr_blocks = ["10.10.0.0/16"]
    from_port   = 9308
    to_port     = 9308
    protocol    = "tcp"
    description = "kafka-exporter from monitoring server"
  }

  tags = {
    Name = "${var.environment}-sg-kafka-private"
  }
}

# ──────────────────────────────────────────────
# EC2 — Kafka Brokers (Private)
# - broker-1/2를 서로 다른 private subnet에 배치(AZ 분산)
# - Public IP/EIP 미사용
# - SSH는 Caddy 점프호스트 경유
# ──────────────────────────────────────────────

module "ec2_kafka_1" {
  source = "../../modules/ec2"

  environment                 = var.environment
  purpose                     = "kafka-1"
  instance_type               = "t3.medium"
  ami_id                      = data.aws_ami.docker_base.id
  subnet_id                   = module.vpc.private_subnet_ids[0]
  security_group_ids          = [aws_security_group.kafka_private.id]
  associate_public_ip_address = false
  manage_key_pair             = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_common.name
}

module "ec2_kafka_2" {
  source = "../../modules/ec2"

  environment                 = var.environment
  purpose                     = "kafka-2"
  instance_type               = "t3.medium"
  ami_id                      = data.aws_ami.docker_base.id
  subnet_id                   = module.vpc.private_subnet_ids[1]
  security_group_ids          = [aws_security_group.kafka_private.id]
  associate_public_ip_address = false
  manage_key_pair             = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_common.name
}

# ──────────────────────────────────────────────
# IAM — Common EC2 Analytics S3 Access
# ──────────────────────────────────────────────

resource "aws_iam_role" "ec2_common" {
  name = "${var.environment}-ec2-common-role"

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

resource "aws_iam_role_policy_attachment" "ec2_common_ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_common.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ec2_common_analytics_s3" {
  name = "${var.environment}-ec2-analytics-s3-policy"
  role = aws_iam_role.ec2_common.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.analytics.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.analytics.arn}/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_common" {
  name = "${var.environment}-ec2-common-instance-profile"
  role = aws_iam_role.ec2_common.name
}

# ──────────────────────────────────────────────
# IAM — Backend ASG S3 Access
# ──────────────────────────────────────────────

resource "aws_iam_role_policy" "asg_spring_uploads_s3" {
  name = "uploads-s3-access"
  role = module.asg_spring.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.uploads.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "asg_spring_analytics_s3" {
  name = "analytics-s3-access"
  role = module.asg_spring.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.analytics.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.analytics.arn}/*"
      },
    ]
  })
}

# ──────────────────────────────────────────────
# CodeDeploy — Backend
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

resource "aws_codedeploy_deployment_group" "backend_stg" {
  app_name              = aws_codedeploy_app.backend.name
  deployment_group_name = var.codedeploy_deployment_group_name
  service_role_arn      = aws_iam_role.codedeploy_service.arn

  deployment_config_name = "CodeDeployDefault.OneAtATime"
  autoscaling_groups     = [module.asg_spring.asg_name]

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.codedeploy_service,
  ]
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
# RDS — PostgreSQL
# ──────────────────────────────────────────────

module "rds" {
  source = "../../modules/rds"

  environment        = var.environment
  instance_class     = "db.t3.small"
  allocated_storage  = 50
  db_name            = "tasteam"
  username           = var.db_username
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.security.rds_sg_id]
}

# ──────────────────────────────────────────────
# SSM — Redis / RDS 동적 값 저장
# ──────────────────────────────────────────────

moved {
  from = module.ssm.aws_ssm_parameter.this["backend/REDIS_HOST"]
  to   = aws_ssm_parameter.redis_host
}

moved {
  from = module.ssm.aws_ssm_parameter.this["backend/REDIS_PORT"]
  to   = aws_ssm_parameter.redis_port
}

moved {
  from = aws_ssm_parameter.db_username
  to   = module.ssm.aws_ssm_parameter.this["backend/DB_USERNAME"]
}

moved {
  from = aws_ssm_parameter.db_password
  to   = module.ssm.aws_ssm_parameter.this["backend/DB_PASSWORD"]
}

moved {
  from = module.ssm.aws_ssm_parameter.this["fastapi/QDRANT_URL"]
  to   = aws_ssm_parameter.fastapi_qdrant_url
}

resource "aws_ssm_parameter" "redis_host" {
  name        = "/${var.environment}/tasteam/backend/REDIS_HOST"
  type        = "String"
  value       = module.ec2_redis.private_ip
  description = "Redis private IP (Redis EC2에서 자동 생성)"

  tags = {
    Name = "${var.environment}-ssm-backend-REDIS_HOST"
  }
}

resource "aws_ssm_parameter" "redis_port" {
  name        = "/${var.environment}/tasteam/backend/REDIS_PORT"
  type        = "String"
  value       = "6379"
  description = "Redis port (Redis EC2에서 자동 설정)"

  tags = {
    Name = "${var.environment}-ssm-backend-REDIS_PORT"
  }
}

resource "aws_ssm_parameter" "fastapi_qdrant_url" {
  name        = "/${var.environment}/tasteam/fastapi/QDRANT_URL"
  type        = "String"
  value       = "http://${module.ec2_qdrant.private_ip}:6333"
  description = "Qdrant HTTP endpoint for FastAPI (Qdrant EC2에서 자동 생성)"

  tags = {
    Name = "${var.environment}-ssm-fastapi-QDRANT_URL"
  }
}

resource "aws_ssm_parameter" "kafka_bootstrap_servers" {
  name        = "/${var.environment}/tasteam/backend/KAFKA_BOOTSTRAP_SERVERS"
  type        = "String"
  value       = "${module.ec2_kafka_1.private_ip}:9092,${module.ec2_kafka_2.private_ip}:9092"
  description = "Kafka bootstrap servers (Kafka EC2 2대에서 자동 생성)"

  tags = {
    Name = "${var.environment}-ssm-backend-KAFKA_BOOTSTRAP_SERVERS"
  }
}

resource "aws_ssm_parameter" "db_url" {
  name        = "/${var.environment}/tasteam/backend/DB_URL"
  type        = "SecureString"
  value       = "jdbc:postgresql://${module.rds.address}:${module.rds.port}/tasteam"
  description = "PostgreSQL JDBC URL (RDS 모듈에서 자동 생성)"

  tags = {
    Name = "${var.environment}-ssm-backend-DB_URL"
  }
}

resource "aws_ssm_parameter" "cloud_map_service_id" {
  name        = "/${var.environment}/tasteam/backend/CLOUD_MAP_SERVICE_ID"
  type        = "String"
  value       = module.cloud_map.service_id
  description = "Cloud Map service ID for Spring service discovery custom health"

  tags = {
    Name = "${var.environment}-ssm-backend-CLOUD_MAP_SERVICE_ID"
  }
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

# 1. Peering Request (From V2 stg)
resource "aws_vpc_peering_connection" "v1_peering" {
  vpc_id        = module.vpc.vpc_id
  peer_vpc_id   = data.aws_vpc.v1.id
  peer_owner_id = data.aws_caller_identity.v1.account_id
  peer_region   = var.aws_region
  auto_accept   = false

  tags = {
    Name = "stg-pcx-v1"
    Side = "Requester"
  }
}

# 2. Peering Accepter (In V1)
resource "aws_vpc_peering_connection_accepter" "v1_peering_accepter" {
  provider                  = aws.v1
  vpc_peering_connection_id = aws_vpc_peering_connection.v1_peering.id
  auto_accept               = true

  tags = {
    Name = "stg-pcx-v1"
    Side = "Accepter"
  }
}

# 3. Routes: V2 stg -> V1 (Private)
resource "aws_route" "to_v1_private" {
  route_table_id            = module.vpc.private_route_table_id
  destination_cidr_block    = data.aws_vpc.v1.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.v1_peering.id
}

# 4. Routes: V2 stg -> V1 (Public)
resource "aws_route" "to_v1_public" {
  route_table_id            = module.vpc.public_route_table_id
  destination_cidr_block    = data.aws_vpc.v1.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.v1_peering.id
}

# 5. Routes: V1 -> V2 stg (Main Route Table)
resource "aws_route" "v1_to_stg" {
  provider                  = aws.v1
  route_table_id            = data.aws_route_table.v1.id
  destination_cidr_block    = module.vpc.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.v1_peering.id
}
