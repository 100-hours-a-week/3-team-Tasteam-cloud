terraform {
  # Terraform CLI 버전 제약 조건
  # ">= 1.0.0": 1.0.0 버전 이상이면 어떤 버전이든 허용 (너무 광범위함)
  # "~> 1.14": 1.14.x 버전까지만 허용하고 1.15.0 이상은 허용하지 않음 (안전함)
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # AWS Provider 버전 제약 조건
      # ">= 5.0.0": 5.0.0 이상이면 메이저 버전 업데이트도 허용할 수 있음 (위험할 수 있음)
      # "~> 6.28": 6.28.x 버전대에서 가장 최신 버전을 사용, 6.29 이상으로는 자동 업데이트 안됨 (안정성 확보)
      version = "~> 6.28"
    }
  }

  backend "s3" {
    bucket       = "terraform-state-mvp-bucket"
    key          = "terraform/terraform.tfstate"
    region       = "ap-northeast-2"
    profile      = "tasteam-v1"
    use_lockfile = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "tasteam-v1"
}
