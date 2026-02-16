terraform {
  backend "s3" {
    bucket       = "tasteam-v2-tfstate"
    key          = "v2-docker/dev/terraform.tfstate"
    region       = "ap-northeast-2"
    profile      = "tasteam-v2"
    use_lockfile = true
  }
}
