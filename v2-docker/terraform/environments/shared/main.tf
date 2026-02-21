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
# EC2 — Monitoring (PLG Stack)
# ──────────────────────────────────────────────

module "ec2_monitoring" {
  source = "../../modules/ec2"

  environment        = var.environment
  purpose            = "monitoring"
  instance_type      = "t3.medium"
  ami_id             = data.aws_ami.docker_base.id
  subnet_id          = module.vpc.private_subnet_ids[0]
  security_group_ids = [module.security.monitoring_sg_id]
  manage_key_pair    = true
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
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*"
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
          "codedeploy:GetDeploymentConfig"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::${var.codedeploy_artifact_bucket_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
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
          "ecr:UploadLayerPart"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"
      }
    ]
  })
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
