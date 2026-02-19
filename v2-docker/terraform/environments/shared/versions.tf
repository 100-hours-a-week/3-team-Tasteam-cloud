terraform {
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.32"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "tasteam-v2"

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "tasteam"
      ManagedBy   = "terraform"
    }
  }
}
