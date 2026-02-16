terraform {
  # Terraform CLI 버전 제약 조건
  # "~> 1.14": 1.14.x 버전까지만 허용하고 1.15.0 이상은 허용하지 않음 (안전함)
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # AWS Provider 버전 제약 조건
      # "~> 6.28": 6.28.x 버전대에서 가장 최신 버전을 사용, 6.29 이상으로는 자동 업데이트 안됨 (안정성 확보)
      version = "~> 6.28"
    }
  }

  backend "s3" {
    bucket       = "terraform-state-mvp-bucket"
    key          = "terraform-dev/terraform.tfstate"
    region       = "ap-northeast-2"
    profile      = "tasteam-v1"
    use_lockfile = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "tasteam-v1"
}
