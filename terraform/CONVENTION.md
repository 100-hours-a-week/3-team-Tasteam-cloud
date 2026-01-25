# Terraform 작성 컨벤션

프로젝트의 일관성과 유지보수성을 위해 다음과 같은 Terraform 코드 작성 규칙을 따릅니다.

## 1. 파일 구조 (File Structure)
코드의 역할에 따라 파일을 명확히 분리합니다.

| 파일명 | 설명 |
|---|---|
| `main.tf` | 핵심 리소스(Resource) 및 데이터 소스(Data Source) 정의 |
| `variables.tf` | 입력 변수(`variable`) 정의 |
| `outputs.tf` | 출력 값(`output`) 정의 |
| `versions.tf` | Terraform 버전 및 Provider 설정 (`terraform`, `provider` 블록) |
| `backend.tf` | Backend 설정 (State 파일 저장소 설정) |
| `locals.tf` | 로컬 변수(`locals`) 정의 (복잡한 표현식 단순화 목적) |
| `*.auto.tfvars` | 자동으로 로드되는 변수 값 파일 |

## 2. 네이밍 규칙 (Naming Rules)

### 리소스 및 변수 식별자 (Identifiers)
- **Snake Case** (`resource_name`) 사용을 원칙으로 합니다.
  - Good: `aws_instance.web_server`
  - Bad: `aws_instance.web-server`, `aws_instance.webServer`
- 유니크해야 하는 `Name` 태그 값 등 외부로 보여지는 값은 **Kebab Case** (`resource-name`)를 허용합니다.

### 중복 방지
- 리소스 이름에 리소스 타입을 반복하지 않습니다.
  - Bad: `resource "aws_route_table" "public_route_table" {}`
  - Good: `resource "aws_route_table" "public" {}` (이미 `aws_route_table` 타입이 명시됨)

## 3. 스타일 및 포맷팅 (Style & Formatting)
- **terraform fmt**: 커밋 전 반드시 `terraform fmt` 명령어를 실행하여 스타일을 통일합니다.
- **들여쓰기**: 스페이스 2칸을 사용합니다.
- **정렬**: 속성 정의 시 등호(`=`)의 위치를 맞춰 가독성을 높입니다.

```hcl
resource "aws_instance" "example" {
  ami           = "ami-12345678"
  instance_type = "t2.micro"
}
```

## 4. 모범 사례 (Best Practices)
- **버전 고정**: `versions.tf`에서 Terraform 및 Provider의 버전을 명시적으로 고정하여 호환성 문제를 방지합니다.
- **하드코딩 지양**: 리전, 인스턴스 타입, AMI ID 등 변경 가능한 값은 `variables.tf`로 추출하거나 `data` 소스를 활용합니다.
- **민감 정보 보호**: 패스워드나 키 값은 코드에 하드코딩하지 않고 환경 변수(`TF_VAR_...`)나 비밀 관리 도구를 사용합니다.

## 5. 코드 간결성 (Conciseness)
- **불필요한 속성 제거**: `null` 값, 빈 리스트/맵(`[]`, `{}`), Provider 기본값(`false` 등)은 코드 가독성을 위해 생략합니다.
- **불필요한 메타데이터 제거**: `terraform plan -generate-config-out` 등으로 생성된 코드에서 `id`, `arn`, `created_at` 등 관리되지 않아도 되는 속성은 제거합니다.
