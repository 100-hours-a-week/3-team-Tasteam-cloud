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
  key_name           = var.key_name
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
