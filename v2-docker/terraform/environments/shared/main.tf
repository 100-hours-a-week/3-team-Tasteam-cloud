# ──────────────────────────────────────────────
# Network — VPC, Subnets, IGW, Route Tables
# ──────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  environment          = var.environment
  vpc_cidr             = "10.10.0.0/16"
  public_subnet_cidrs  = ["10.10.0.0/20", "10.10.16.0/20"]
  private_subnet_cidrs = ["10.10.128.0/20", "10.10.144.0/20"]
  availability_zones   = ["ap-northeast-2a", "ap-northeast-2c"]
}

# ──────────────────────────────────────────────
# Security Groups
# ──────────────────────────────────────────────

module "security" {
  source = "../../modules/security"

  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  enable_monitoring = true
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
# IAM — Monitoring EC2 Role
# Prometheus EC2 SD + Grafana CloudWatch + SSM 파라미터 읽기
# ──────────────────────────────────────────────

resource "aws_iam_role" "monitoring" {
  name = "${var.environment}-tasteam-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.environment}-tasteam-monitoring-profile"
  role = aws_iam_role.monitoring.name
}

# ── Prometheus EC2 Service Discovery ──
resource "aws_iam_role_policy" "monitoring_ec2_sd" {
  name = "ec2-service-discovery"
  role = aws_iam_role.monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",
        "ec2:DescribeTags",
        "ec2:DescribeInstances"
      ]
      Resource = "*"
    }]
  })
}

# ── Grafana CloudWatch 데이터소스 ──
resource "aws_iam_role_policy" "monitoring_cloudwatch" {
  name = "cloudwatch-read"
  role = aws_iam_role.monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:DescribeAlarmsForMetric",
        "cloudwatch:DescribeAlarmHistory",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricData",
        "cloudwatch:GetInsightRuleReport"
      ]
      Resource = "*"
    }]
  })
}

# ── SSM 모니터링 파라미터 읽기 ──
resource "aws_iam_role_policy" "monitoring_ssm" {
  name = "ssm-read"
  role = aws_iam_role.monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:*:*:parameter/*/tasteam/monitoring/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
      }
    ]
  })
}

# ── CodeDeploy Artifacts & Agent ──
resource "aws_iam_role_policy" "monitoring_codedeploy" {
  name = "codedeploy-read"
  role = aws_iam_role.monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::${var.codedeploy_artifact_bucket_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning"
        ]
        Resource = "arn:aws:s3:::${var.codedeploy_artifact_bucket_name}"
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
      }
    ]
  })
}

# ──────────────────────────────────────────────
# CodeDeploy — Monitoring
# ──────────────────────────────────────────────

resource "aws_iam_role" "codedeploy_monitoring" {
  name = "${var.environment}-codedeploy-monitoring-role"

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

resource "aws_iam_role_policy_attachment" "codedeploy_monitoring" {
  role       = aws_iam_role.codedeploy_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

resource "aws_codedeploy_app" "monitoring" {
  compute_platform = "Server"
  name             = "${var.environment}-tasteam-monitoring"
}

resource "aws_codedeploy_deployment_group" "monitoring" {
  app_name              = aws_codedeploy_app.monitoring.name
  deployment_group_name = "${var.environment}-tasteam-monitoring-dg"
  service_role_arn      = aws_iam_role.codedeploy_monitoring.arn

  deployment_config_name = "CodeDeployDefault.OneAtATime"

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Purpose"
      type  = "KEY_AND_VALUE"
      value = "monitoring"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.codedeploy_monitoring
  ]
}

# ──────────────────────────────────────────────
# EC2 — Caddy (Monitoring 리버스 프록시)
# 인터넷 → Caddy (public subnet) → monitoring EC2 (private subnet)
# ──────────────────────────────────────────────

module "ec2_caddy" {
  source = "../../modules/ec2"

  environment                 = var.environment
  purpose                     = "caddy"
  instance_type               = "t3.micro"
  ami_id                      = "ami-00b6cd96f80a61923"
  subnet_id                   = module.vpc.public_subnet_ids[0]
  security_group_ids          = [module.security.app_sg_id]
  associate_public_ip_address = true
  manage_key_pair             = true
}

# ──────────────────────────────────────────────
# EC2 — Monitoring (PLG Stack)
# ──────────────────────────────────────────────

module "ec2_monitoring" {
  source = "../../modules/ec2"

  environment                = var.environment
  purpose                    = "monitoring"
  instance_type              = "t3.medium"
  ami_id                     = "ami-00b6cd96f80a61923"
  subnet_id                  = module.vpc.private_subnet_ids[0]
  security_group_ids         = [module.security.monitoring_sg_id]
  manage_key_pair            = true
  iam_instance_profile       = aws_iam_instance_profile.monitoring.name
  private_ip                 = "10.10.131.197"
  root_delete_on_termination = false
}

# ──────────────────────────────────────────────
# EBS — Monitoring 데이터 볼륨
# Prometheus, Loki, Grafana 데이터를 별도 볼륨에 저장
# 인스턴스가 삭제/교체되어도 데이터는 절대 소실되지 않음
# ──────────────────────────────────────────────

resource "aws_ebs_volume" "monitoring_data" {
  availability_zone = "ap-northeast-2a"
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = {
    Name    = "${var.environment}-ebs-monitoring-data"
    Purpose = "monitoring-data"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "monitoring_data" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.monitoring_data.id
  instance_id  = module.ec2_monitoring.instance_id
  force_detach = true
}

# ──────────────────────────────────────────────
# NAT Instance — monitoring EC2 외부 통신 (Docker Hub)
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
# VPC Peering — shared ↔ prod, stg, dev
# ──────────────────────────────────────────────

data "terraform_remote_state" "prod" {
  backend = "s3"

  config = {
    bucket  = "tasteam-v2-tfstate"
    key     = "v2-docker/prod/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "tasteam-v2"
  }
}

data "terraform_remote_state" "stg" {
  backend = "s3"

  config = {
    bucket  = "tasteam-v2-tfstate"
    key     = "v2-docker/stg/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "tasteam-v2"
  }
}

data "terraform_remote_state" "dev" {
  backend = "s3"

  config = {
    bucket  = "tasteam-v2-tfstate"
    key     = "v2-docker/dev/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "tasteam-v2"
  }
}

module "peering_prod" {
  source = "../../modules/vpc-peering"

  environment              = var.environment
  peer_environment         = "prod"
  requester_vpc_id         = module.vpc.vpc_id
  requester_cidr           = "10.10.0.0/16"
  requester_route_table_id = module.vpc.private_route_table_id
  accepter_vpc_id          = data.terraform_remote_state.prod.outputs.vpc_id
  accepter_cidr            = data.terraform_remote_state.prod.outputs.vpc_cidr_block
  accepter_route_table_id  = data.terraform_remote_state.prod.outputs.private_route_table_id
}

module "peering_stg" {
  source = "../../modules/vpc-peering"

  environment              = var.environment
  peer_environment         = "stg"
  requester_vpc_id         = module.vpc.vpc_id
  requester_cidr           = "10.10.0.0/16"
  requester_route_table_id = module.vpc.private_route_table_id
  accepter_vpc_id          = data.terraform_remote_state.stg.outputs.vpc_id
  accepter_cidr            = data.terraform_remote_state.stg.outputs.vpc_cidr_block
  accepter_route_table_id  = data.terraform_remote_state.stg.outputs.private_route_table_id
}

module "peering_dev" {
  source = "../../modules/vpc-peering"

  environment              = var.environment
  peer_environment         = "dev"
  requester_vpc_id         = module.vpc.vpc_id
  requester_cidr           = "10.10.0.0/16"
  requester_route_table_id = module.vpc.private_route_table_id
  accepter_vpc_id          = data.terraform_remote_state.dev.outputs.vpc_id
  accepter_cidr            = data.terraform_remote_state.dev.outputs.vpc_cidr_block
  accepter_route_table_id  = data.terraform_remote_state.dev.outputs.private_route_table_id
}

# dev Caddy EC2(퍼블릭 서브넷) → shared VPC 피어링 라우트
# private RT에만 피어링 라우트가 있어 Alloy가 push 불가했던 문제 해소
resource "aws_route" "dev_public_to_shared" {
  route_table_id            = data.terraform_remote_state.dev.outputs.public_route_table_id
  destination_cidr_block    = "10.10.0.0/16"
  vpc_peering_connection_id = module.peering_dev.peering_connection_id
}

# prod Caddy EC2(퍼블릭 서브넷) → shared VPC 피어링 라우트
# dev와 동일 이슈: Caddy의 Alloy가 shared Loki/Prometheus에 push 불가
data "aws_route_table" "prod_public" {
  vpc_id = data.terraform_remote_state.prod.outputs.vpc_id

  filter {
    name   = "tag:Name"
    values = ["prod-rtb-public"]
  }
}

resource "aws_route" "prod_public_to_shared" {
  route_table_id            = data.aws_route_table.prod_public.id
  destination_cidr_block    = "10.10.0.0/16"
  vpc_peering_connection_id = module.peering_prod.peering_connection_id
}

# ──────────────────────────────────────────────
# S3 — CodeDeploy Artifact Bucket
# ──────────────────────────────────────────────

resource "aws_s3_bucket" "codedeploy_artifacts" {
  bucket = var.codedeploy_artifact_bucket_name

  tags = {
    Name = "${var.environment}-codedeploy-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "codedeploy_artifacts" {
  bucket = aws_s3_bucket.codedeploy_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "codedeploy_artifacts" {
  bucket = aws_s3_bucket.codedeploy_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "codedeploy_artifacts" {
  bucket = aws_s3_bucket.codedeploy_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────────
# IAM — GitHub Actions (Single Role for dev/stg/prod)
# ──────────────────────────────────────────────

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.github_oidc_provider_arn == "" ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  github_oidc_provider_arn_resolved = var.github_oidc_provider_arn != "" ? var.github_oidc_provider_arn : aws_iam_openid_connect_provider.github_actions[0].arn
}

resource "aws_iam_role" "github_actions_deploy" {
  name = "tasteam-github-actions-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.github_oidc_provider_arn_resolved
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        "ForAnyValue:StringLike" = {
          "token.actions.githubusercontent.com:sub" = [for repo in var.github_repositories : "repo:${repo}:*"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "tasteam-github-actions-deploy-policy"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentGroup",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:GetApplicationRevision",
          "codedeploy:GetApplication",
          "codedeploy:ListDeployments",
          "codedeploy:ListDeploymentGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = "arn:aws:s3:::${var.codedeploy_artifact_bucket_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "arn:aws:s3:::${var.codedeploy_artifact_bucket_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:ListImages"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"
      }
    ]
  })
}

# ──────────────────────────────────────────────
# IAM — Backend User (ReadOnly + Parameter Store Full)
# 액세스 키는 tfstate 저장 방지를 위해 AWS 콘솔에서 수동 생성
# ──────────────────────────────────────────────

locals {
  backend_readonly_paramstore_users = toset([
    "sei",
    "devon",
    "jian"
  ])
}

resource "aws_iam_user" "backend_readonly_paramstore" {
  for_each = local.backend_readonly_paramstore_users

  name = each.value
  path = "/"

  tags = {
    Name = each.value
  }
}

resource "aws_iam_user_policy_attachment" "backend_readonly_access" {
  for_each = local.backend_readonly_paramstore_users

  user       = aws_iam_user.backend_readonly_paramstore[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_user_policy_attachment" "backend_change_password" {
  for_each = local.backend_readonly_paramstore_users

  user       = aws_iam_user.backend_readonly_paramstore[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/IAMUserChangePassword"
}

resource "aws_iam_user_login_profile" "backend_console_login" {
  for_each = local.backend_readonly_paramstore_users

  user                    = aws_iam_user.backend_readonly_paramstore[each.key].name
  password_reset_required = true
}

resource "aws_iam_user_policy" "backend_parameter_store_full" {
  for_each = local.backend_readonly_paramstore_users

  name = "parameter-store-full"
  user = aws_iam_user.backend_readonly_paramstore[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:AddTagsToResource",
          "ssm:DeleteParameter",
          "ssm:DeleteParameters",
          "ssm:GetParameter",
          "ssm:GetParameterHistory",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:LabelParameterVersion",
          "ssm:ListTagsForResource",
          "ssm:PutParameter",
          "ssm:RemoveTagsFromResource",
          "ssm:UnlabelParameterVersion"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:DescribeParameters"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })
}

# ──────────────────────────────────────────────
# IAM — Cloud User (Full Access)
# ──────────────────────────────────────────────

resource "aws_iam_user" "backend_full_access_clay" {
  name = "clay"
  path = "/"

  tags = {
    Name = "clay"
  }
}

resource "aws_iam_user_login_profile" "backend_full_access_clay_console_login" {
  user                    = aws_iam_user.backend_full_access_clay.name
  password_reset_required = true
}

resource "aws_iam_user_policy_attachment" "backend_full_access_clay_admin" {
  user       = aws_iam_user.backend_full_access_clay.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ──────────────────────────────────────────────
# ECR — Backend Repository
# ──────────────────────────────────────────────

resource "aws_ecr_repository" "backend" {
  name                 = var.ecr_repository_backend_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.environment}-ecr-backend"
  }
}

# ──────────────────────────────────────────────
# SSM — Monitoring POSTGRES_DSN
# 모니터링 Alloy가 prod RDS에 접속하기 위한 DSN
# Terraform이 RDS 주소 포함한 템플릿 생성, 사용자가 실제 자격증명으로 값 수정
# ──────────────────────────────────────────────

resource "aws_ssm_parameter" "monitoring_postgres_dsn" {
  name        = "/shared/tasteam/monitoring/POSTGRES_DSN"
  type        = "SecureString"
  value       = "postgresql://CHANGE_ME:CHANGE_ME@${data.terraform_remote_state.prod.outputs.rds_address}:${data.terraform_remote_state.prod.outputs.rds_port}/tasteam?sslmode=require"
  description = "Alloy postgres exporter DSN for prod RDS"

  lifecycle {
    ignore_changes = [value]
  }
}
