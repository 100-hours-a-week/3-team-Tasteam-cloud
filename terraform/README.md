# Tasteam Terraform Infrastructure

이 디렉터리는 Tasteam 서비스의 AWS 인프라를 Terraform으로 관리하기 위한 설정을 담고 있습니다.

## 주요 리소스

*   **EC2 Instance**: `dev_single_instance` (개발용 단일 인스턴스)
    *   Docker 환경 최적화 (Hop Limit 조정)
    *   IMDSv2 보안 적용
*   **Networking**: VPC, Subnet, Security Group, EIP 등
*   **Storage**: EBS `gp3` 볼륨

## 시작하기 (Getting Started)

### 사전 요구 사항

*   [Terraform](https://www.terraform.io/) (>= 1.0.0)
*   AWS CLI (설정 및 자격 증명 완료)

### 사용법

1.  **초기화**
    ```bash
    terraform init
    ```

2.  **계획 확인**
    ```bash
    terraform plan
    ```

3.  **적용**
    ```bash
    terraform apply
    ```

## 구조 설명

*   `main.tf`: 주요 리소스 정의 (EC2 Instance, EIP 등 서비스 핵심 리소스)
*   `vpc.tf`: 네트워킹 리소스 정의 (VPC, Subnet, Internet Gateway, Route Table)
*   `security.tf`: 보안 그룹(Security Group) 정의 (인바운드/아웃바운드 규칙)
*   `versions.tf`: Terraform Provider 설정 및 버전 관리
*   `backend.tf`: Terraform State 관리를 위한 Backend 설정
*   `variables.tf`: 재사용 가능한 변수(Variable) 정의 및 기본값 설정
