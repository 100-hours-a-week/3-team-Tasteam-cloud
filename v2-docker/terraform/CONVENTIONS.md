# Terraform Conventions — tasteam v2

## 0. 디렉터리 구조 및 명명 규칙

### 0.1 최상위 디렉터리 구조

```
terraform/
├── CONVENTIONS.md         # 이 문서
├── builds/                # 재사용 가능한 이미지·아티팩트 빌드
│   └── {build-name}/      # kebab-case
├── environments/          # 환경별 루트 모듈
│   ├── dev/
│   ├── prod/
│   ├── shared/
│   └── stg/
└── modules/               # 재사용 가능한 공유 모듈
    ├── ec2/
    ├── iam/
    ├── nat/
    ├── rds/
    ├── s3/
    ├── security/
    ├── ssm/
    ├── vpc/
    └── vpc-peering/
```

### 0.2 디렉터리명 규칙

| 위치 | 규칙 | 예시 |
|------|------|------|
| `builds/` 하위 | **kebab-case**, 빌드 목적 기술 | `docker-ami` |
| `environments/` 하위 | 환경명 그대로 | `dev`, `prod`, `stg`, `shared` |
| `modules/` 하위 | **kebab-case**, AWS 리소스 또는 역할 단위 | `vpc`, `vpc-peering`, `ec2` |

- 대문자·언더스코어 사용 금지
- 약어는 소문자 (예: `iam`, `rds`, `vpc`)

---

## 1. 네이밍 컨벤션

### 1.1 AWS Name 태그 (콘솔 표시명)

```
{env}-{resource-type}-{purpose}[-{suffix}]
```

| 세그먼트 | 규칙 | 예시 |
|----------|------|------|
| env | `prod`, `dev`, `stg` | prod |
| resource-type | AWS 리소스 약어 (아래 표) | vpc, subnet, ec2, rds |
| purpose | 역할/용도 | main, app, public, private |
| suffix (선택) | AZ, 번호 등 구분 필요시 | 2a, 2c, 01 |

#### 리소스 타입 약어

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
| Key Pair | kp |
| SSM Parameter | ssm |
| Launch Template | lt |
| Auto Scaling Group | asg |

#### Name 태그 예시

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

### 1.2 Terraform 리소스명 (`resource "aws_xxx" "THIS"`)

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

### 1.3 S3 버킷명 (글로벌 고유)

```
{env}-tasteam-{purpose}
```

- 글로벌 고유 → 프로젝트명 포함
- 예: `prod-tasteam-uploads`, `dev-tasteam-uploads`

### 1.4 IAM 리소스명

```
{env}-tasteam-{purpose}
```

- 계정 레벨 → 프로젝트명 포함
- 예: `prod-tasteam-ec2-s3-role`, `dev-tasteam-ec2-s3-role`

### 1.5 RDS Identifier

```
{env}-tasteam-{purpose}
```

- 리전 내 고유 → 프로젝트명 포함
- 예: `prod-tasteam-main`, `dev-tasteam-main`

### 1.6 SSM Parameter Store 경로

```
/{env}/tasteam/{service}/{parameter-key}
```

| 세그먼트 | 규칙 | 예시 |
|----------|------|------|
| env | `prod`, `dev`, `stg` | prod |
| tasteam | 프로젝트명 (고정) | tasteam |
| service | 서비스 네임스페이스 | `backend`, `frontend`, `fastapi`, `monitoring` |
| parameter-key | 서비스별 키 규칙 | 아래 표 참고 |

#### 서비스별 키 규칙

| service | 키 규칙 | 예시 |
|--------|---------|------|
| backend | `UPPER_SNAKE_CASE` | `DB_URL`, `JWT_SECRET` |
| frontend | `UPPER_SNAKE_CASE` | `VITE_APP_ENV`, `VITE_API_BASE_URL` |
| fastapi | `slash + kebab-case` | `openai-api-key`, `db-url` |
| monitoring | `slash + kebab-case` | `grafana-admin-password` |

#### 경로 예시

```
/prod/tasteam/backend/DB_URL
/prod/tasteam/backend/JWT_SECRET
/prod/tasteam/frontend/VITE_API_BASE_URL
/prod/tasteam/fastapi/openai-api-key
/prod/tasteam/monitoring/grafana-admin-password
```
---

## 2. 태그 컨벤션

### 2.1 공통 태그

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

### 2.2 리소스별 태그

개별 리소스에는 **`Name` 태그만** 선언한다:

```hcl
tags = {
  Name = "{env}-{type}-{purpose}"
}
```

> `default_tags`와 리소스 `tags`에 같은 키가 있으면 리소스의 값이 우선한다.

---

## 3. 운영 가이드

### 3.1 SSM Parameter Store

- `SecureString` 타입은 AWS KMS 기본 키(`aws/ssm`)로 암호화
- 값은 Terraform이 아닌 AWS 콘솔/CLI에서 직접 설정
- Name 태그: `{env}-ssm-{service}-{parameter-name}` (슬래시를 하이픈으로 치환)
- 키 네이밍 검증: `modules/ssm/variables.tf`의 `validation`에서 서비스별 패턴을 강제

---

## 4. 파일명 규칙

### 4.1 표준 파일

모든 환경(`environments/{env}/`) 및 모듈(`modules/{name}/`)은 아래 표준 파일을 사용한다.

| 파일명 | 포함 내용 | 필수 여부 |
|--------|-----------|-----------|
| `main.tf` | 핵심 리소스(`resource`) 및 데이터 소스(`data`) | 필수 |
| `variables.tf` | 입력 변수(`variable`) 선언 | 필수 |
| `outputs.tf` | 출력 값(`output`) 선언 | 필수 |
| `versions.tf` | Terraform 버전 요구사항 및 `provider` 블록 | 환경에만 필수 |
| `backend.tf` | 원격 State 저장소 설정(`backend`) | 환경에만 필수 |
| `locals.tf` | 로컬 변수(`locals`) — 복잡한 표현식 단순화 목적 | 선택 |

### 4.2 추가 파일

역할이 명확히 구분되는 리소스는 별도 파일로 분리할 수 있다.

| 파일명 패턴 | 용도 | 예시 |
|------------|------|------|
| `{role}.tf` | 특정 역할 리소스만 담는 파일 | `key_pair.tf` |
| `terraform.tfvars.example` | tfvars 작성 예시 (커밋 허용) | — |
| `terraform.tfvars` | 실제 변수 값 파일 (**커밋 금지**) | — |

### 4.3 파일명 작성 규칙

- **snake_case** 사용 (하이픈 금지)
  - Good: `key_pair.tf`
  - Bad: `key-pair.tf`
- 파일명은 **영문 소문자**만 사용
- 역할이 불분명한 `misc.tf`, `other.tf` 같은 이름은 금지
  - 파일이 한 곳에 맞지 않으면 리소스를 더 작은 역할 단위로 쪼개거나 `{specific_role}.tf`로 분리한다
  - 예: 한 파일에 IAM·CodeDeploy가 섞이면 → `iam.tf` + `codedeploy.tf`로 분리

---

## 5. 디스크립션 규칙

### 5.1 `variable` 디스크립션

- **필수**: 모든 `variable` 블록에 `description`을 작성한다.
- **언어**: **한글**을 기본으로 한다. AWS 서비스명·enum 값 등 고유명사는 영문 병기를 허용한다.
- **내용**: 변수의 역할·제약·기본값 이유를 간결하게 설명한다.

```hcl
# Good — 한글 기본
variable "environment" {
  description = "환경 이름 (prod, dev, stg, shared)"
  type        = string
}

# Good — 한국어 + 고유명사 영문 병기
variable "manage_key_pair" {
  description = "true 시 tls_private_key + aws_key_pair를 모듈 내에서 자동 생성"
  type        = bool
  default     = false
}

# Bad — 디스크립션 없음
variable "ami_id" {
  type = string
}
```

### 5.2 `output` 디스크립션

- **필수**: 모든 `output` 블록에 `description`을 작성한다.
- 출력값이 어떤 리소스의 어떤 속성인지 **한글**로 명시한다.

```hcl
# Good
output "vpc_id" {
  description = "VPC 아이디"
  value       = aws_vpc.main.id
}

# Good — 조건부 출력인 경우 조건 명시
output "key_pair_name" {
  description = "AWS 키 페어 이름 (manage_key_pair=false 시 null)"
  value       = one(aws_key_pair.this[*].key_name)
}
```

### 5.3 `resource` / `data` 디스크립션

`resource`·`data` 블록 자체에는 `description` 속성이 없으므로 **섹션 주석**으로 대체한다 (아래 6절 참조).

단, Security Group 등 `description` 인수를 지원하는 리소스는 반드시 작성한다.

```hcl
# Good
resource "aws_security_group" "app" {
  description = "애플리케이션 서버 보안 그룹"
  ...
}

# Bad
resource "aws_security_group" "app" {
  description = "managed by terraform"   # 의미 없는 기본 문구
  ...
}
```

---

## 6. 주석 규칙

### 6.1 섹션 구분자 (Section Divider)

논리적으로 연관된 리소스 그룹의 시작에 아래 형식의 구분자를 사용한다.

```hcl
# ──────────────────────────────────────────────
# {섹션 제목} — {간단한 설명} (선택)
# ──────────────────────────────────────────────
```

- 구분자 줄: `#` + 공백 + `─` 46개
- 제목 줄: `# {제목}` — 제목은 **한글**을 기본으로 한다. AWS 서비스명 등 고유명사는 영문 병기 허용
- 선택적으로 제목 아래에 보충 설명 줄을 추가할 수 있다.
- 구분자 뒤에는 빈 줄 하나를 둔다.

```hcl
# 예시
# ──────────────────────────────────────────────
# VPC
# ──────────────────────────────────────────────

resource "aws_vpc" "main" { ... }

# ──────────────────────────────────────────────
# Key Pair — 조건부 자동 생성
# manage_key_pair = true 시에만 리소스 생성
# ──────────────────────────────────────────────
```

### 6.2 서브섹션 구분자 (Sub-section Divider)

`main.tf` 내에서 그룹 안의 소항목(예: SSM 파라미터 서비스 구분)은 아래 형식을 사용한다.

```hcl
# ── {소항목 제목} ──
```

```hcl
# 예시 (SSM 파라미터 맵 내부)
# ── Spring Boot: DB ──
"backend/DB_URL"      = { type = "SecureString", description = "PostgreSQL JDBC URL" }
"backend/DB_USERNAME" = { type = "SecureString", description = "DB username" }

# ── Spring Boot: Redis ──
"backend/REDIS_HOST" = { type = "String", description = "Redis host" }
```

### 6.3 인라인 주석

- 코드 줄 끝에 `  # {설명}` 형태로 작성한다 (공백 2칸).
- 자명한 코드(예: 표준 속성 참조 `vpc_id = aws_vpc.main.id` 등)에는 달지 않는다.
- 조건 분기, 비직관적인 수식, 외부 의존성이 있는 곳에 달아 동작을 명시한다.

```hcl
# Good
key_name = var.manage_key_pair ? one(aws_key_pair.this[*].key_name) : var.key_name
# manage_key_pair=true → key_pair.tf에서 생성한 키 참조
# manage_key_pair=false → 외부 주입 key_name 또는 null

# Bad — 코드를 그대로 반복하는 불필요한 주석
vpc_id = aws_vpc.main.id  # VPC의 ID를 참조
```

### 6.4 TODO / NOTE 주석

- `TODO:` 미결 작업, `NOTE:` 중요 참고사항 접두사를 사용한다.

```hcl
# TODO: prod 배포 전 AMI ID를 data source로 교체
# NOTE: 이 값은 Terraform이 아닌 AWS 콘솔에서 직접 설정
```
