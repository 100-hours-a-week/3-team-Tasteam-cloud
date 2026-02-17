# Terraform Naming Convention — tasteam v2

## AWS Name 태그 (콘솔 표시명)

```
{env}-{resource-type}-{purpose}[-{suffix}]
```

| 세그먼트 | 규칙 | 예시 |
|----------|------|------|
| env | `prod`, `dev`, `stg` | prod |
| resource-type | AWS 리소스 약어 (아래 표) | vpc, subnet, ec2, rds |
| purpose | 역할/용도 | main, app, public, private |
| suffix (선택) | AZ, 번호 등 구분 필요시 | 2a, 2c, 01 |

### 리소스 타입 약어

| AWS 리소스 | 약어 |
|-----------|------|
| VPC | vpc |
| Subnet | subnet |
| Internet Gateway | igw |
| NAT Gateway | nat |
| Route Table | rtb |
| EC2 Instance | ec2 |
| Elastic IP | eip |
| Security Group | sg |
| RDS Instance | rds |
| DB Subnet Group | db-subnet-group |
| DB Parameter Group | db-params |
| S3 Bucket | s3 |
| IAM Role | role |
| IAM Policy | policy |
| CloudFront | cf |
| Load Balancer | alb / nlb |
| Target Group | tg |

### Name 태그 예시

```
prod-vpc-main
prod-subnet-public-2a
prod-subnet-private-2a
prod-igw-main
prod-rtb-public
prod-rtb-private
prod-ec2-app-01
prod-eip-app
prod-sg-app
prod-sg-rds
prod-rds-main
prod-db-subnet-group-main
prod-db-params-main
prod-s3-uploads
prod-role-ec2-s3
```

---

## Terraform 리소스명 (`resource "aws_xxx" "THIS"`)

```
{purpose}[_{suffix}]
```

- 언더스코어 `_` 구분 (Terraform 규칙)
- 환경 접두사 불포함 — 환경은 workspace/tfvars로 분리
- 예: `main`, `public_2a`, `private_2a`, `app`, `app_01`

```hcl
resource "aws_vpc" "main" {}
resource "aws_subnet" "public_2a" {}
resource "aws_subnet" "private_2a" {}
resource "aws_instance" "app" {}
resource "aws_db_instance" "main" {}
resource "aws_security_group" "app" {}
resource "aws_security_group" "rds" {}
```

---

## S3 버킷명 (글로벌 고유)

```
{env}-tasteam-{purpose}
```

- 글로벌 고유 → 프로젝트명 포함
- 예: `prod-tasteam-uploads`, `dev-tasteam-uploads`

---

## IAM 리소스명

```
{env}-tasteam-{purpose}
```

- 계정 레벨 → 프로젝트명 포함
- 예: `prod-tasteam-ec2-s3-role`, `dev-tasteam-ec2-s3-role`

---

## RDS Identifier

```
{env}-tasteam-{purpose}
```

- 리전 내 고유 → 프로젝트명 포함
- 예: `prod-tasteam-main`, `dev-tasteam-main`

---

## 공통 태그

`Environment`, `Project`, `ManagedBy` 태그는 **provider `default_tags`** 로 자동 적용된다.
각 environment의 `versions.tf`에서 한 번만 선언하면 모든 AWS 리소스에 일괄 적용된다.

```hcl
# environments/{env}/versions.tf
provider "aws" {
  ...
  default_tags {
    tags = {
      Environment = var.environment    # prod, dev, stg
      Project     = "tasteam"
      ManagedBy   = "terraform"
    }
  }
}
```

개별 리소스에는 **`Name` 태그만** 선언한다:

```hcl
tags = {
  Name = "{env}-{type}-{purpose}"
}
```

> `default_tags`와 리소스 `tags`에 같은 키가 있으면 리소스의 값이 우선한다.
