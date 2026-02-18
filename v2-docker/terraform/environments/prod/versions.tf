terraform {
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.32"
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

provider "aws" {
  alias   = "v1"
  region  = var.aws_region
  profile = "tasteam-v1"

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "tasteam"
      ManagedBy   = "terraform"
    }
  }
}
