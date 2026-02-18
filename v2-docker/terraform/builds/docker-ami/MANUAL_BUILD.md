# 수동 Docker AMI 생성 가이드

Terraform에서 재사용할 Docker가 설치된 Ubuntu AMI를 수동으로 생성하는 절차입니다.

## 1. EC2 인스턴스 생성 (Baking용)
AWS 콘솔에서 다음 설정으로 EC2 인스턴스를 하나 띄웁니다.
- **AMI**: Ubuntu Server 22.04 LTS (HVM)
- **Architecture**: x86_64 (또는 arm64, 프로젝트 환경에 맞게)
- **Instance Type**: t3.micro (설치만 하므로 작아도 됨)
- **Key Pair**: 접속 가능한 키 페어 선택
- **Network**: Public Subnet (인터넷 통신 필요)
- **Security Group**: SSH(22) 허용

## 2. Docker 설치
인스턴스가 실행(Running) 상태가 되면 접속하여 Docker를 설치합니다.

### 방법: 웹 콘솔(EC2 Instance Connect)에서 스크립트 붙여넣기
가장 간편한 방법입니다. `install_docker.sh` 내용을 복사한 뒤, 터미널에 붙여넣어 실행합니다.

1. AWS 콘솔에서 인스턴스 선택 > **Connect** > **EC2 Instance Connect** > **Connect** 클릭.
2. 터미널이 열리면 다음 명령어로 파일 생성:
   ```bash
   nano install_docker.sh
   ```
3. `install_docker.sh` 파일 내용을 복사해서 붙여넣기 (Command/Ctrl + V).
4. `Ctrl + O` (저장) > `Enter` > `Ctrl + X` (종료).
5. 스크립트 실행:
   ```bash
   chmod +x install_docker.sh
   ./install_docker.sh
   ```

### 설치 확인
```bash
docker --version
# ubuntu 계정이 docker 그룹에 추가되었는지 확인 (로그아웃 후 다시 로그인 필요할 수 있음)
docker ps
```

## 3. AMI 이미지 생성
1. AWS 콘솔 > EC2 > Instances > 해당 인스턴스 선택.
2. Actions > Image and templates > **Create image**.
3. **Image name**: `shared-ami-docker-v1` (컨벤션: `{env}-{type}-{purpose}`)
4. **Description**: Ubuntu 22.04 with Docker (Manual Build)
5. **No reboot**: 체크 해제 (안전한 생성을 위해 재부팅 권장)
6. **Tags** (중요: 테라폼 조회를 위해 정확히 입력):
   - `Name`: `shared-ami-docker`
   - `Role`: `docker-node`
   - `Version`: `v1.0`
   - `ManagedBy`: `manual`

## 4. Terraform에서 사용하기
`main.tf` 또는 `data.tf`에서 다음과 같이 태그 기반으로 최신 이미지를 가져오도록 설정합니다.

```hcl
data "aws_ami" "docker_base" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["shared-ami-docker-*"] # 네이밍 컨벤션 패턴
  }

  filter {
    name   = "tag:Version"
    values = ["v1.0"] # 필요시 특정 버전 고정
  }
}

resource "aws_instance" "app_server" {
  ami = data.aws_ami.docker_base.id
  # ... 나머지 설정
}
```

## 5. (선택) Baking용 인스턴스 종료
AMI 생성이 완료되면(Available 상태), 1번에서 생성한 EC2 인스턴스는 종료(Terminate)합니다.

## 6. 버전 히스토리 (Version History)
수동으로 생성한 AMI ID를 이곳에 기록하여 관리합니다.

| 버전 (Version) | AMI ID | 리전 (Region) | 기반 OS | 생성일 | 비고 (Notes) |
|:---:|:---:|:---:|:---:|:---:|:---|
| v1.0 | `ami-0b386a10266f47623` | ap-northeast-2 | Ubuntu 22.04 | 2026-02-18 | 웹 콘솔에서 스크립트 실행으로 설치 완료 |
