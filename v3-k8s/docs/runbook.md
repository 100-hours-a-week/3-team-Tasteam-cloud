# kubeadm Prod VPC Runbook

## 0. 문서 목적

- 이 문서는 `prod-vpc-main (10.11.0.0/16)` 위에 **기존 v2 인프라를 유지한 채** 병렬 kubeadm 클러스터를 올리고, `app-prod` 를 배포/검증하기 위한 실행 런북이다.
- 설계 기준 문서는 `v3-k8s/docs/05-kubeadm.md` 이다.
- 이번 범위는 다음 두 트랙을 한 문서에서 다룬다.
  - **Track A**: `cp1 + worker2` 리허설 클러스터
  - **Track B**: `cp3 + worker4` 운영형 확장
- 이번 범위에서 하지 않는 것:
  - Cloudflare origin 최종 절체
  - v2 `asg_spring` / `ec2_caddy` / 현재 RDS/Redis 교체
  - 모니터링 스택 이전
  - `app-dev`, `app-stg` 온보딩

## 1. Source of Truth / 전제

- Source of truth: `v3-k8s/docs/05-kubeadm.md`
- 예전 ALB 기반 설계 문서는 **과거 결정**으로만 취급한다. 이번 실행 경로는 `public NLB -> ingress-nginx NodePort -> ClusterIP` 로 고정한다.
- 노드 OS는 Ubuntu LTS, 컨테이너 런타임은 `containerd`, Kubernetes minor 는 `v1.34.x` 로 고정한다.
- Pod CIDR 은 `10.244.0.0/16`, Service CIDR 은 `10.96.0.0/12` 로 고정한다.
- 상태 저장 계층은 이번 런북에서 클러스터 외부를 유지한다.
  - Spring Boot -> 현재 prod RDS / Redis
  - FastAPI -> 현재 prod DB URL 또는 별도 AI DB URL
- Spring/FastAPI 이미지가 모두 pull 가능한 상태여야 한다.
  - Spring Boot ECR URL 은 `shared` Terraform output 으로 확인한다.
  - FastAPI 이미지 레지스트리는 AI 레포 CI 기준 값을 사전에 확보한다. 없다면 Phase 4 진입 전 먼저 준비한다.
- 노드 루트 볼륨은 `50GB gp3` 를 최소값으로 사용한다.
- EC2 메타데이터 옵션의 `http_put_response_hop_limit = 2` 는 유지한다.
  - 현재 애플리케이션이 인스턴스 프로파일 기반 AWS SDK 자격증명에 의존할 수 있기 때문이다.

## 2. 트랙별 토폴로지

### 2.1 Track A

| 이름 | 역할 | AZ | 서브넷 | 타입 | 루트 디스크 |
| --- | --- | --- | --- | --- | --- |
| `prod-ec2-k8s-cp-2a` | control-plane | `ap-northeast-2a` | `prod-subnet-private-2a` | `t3.medium` | `50GB gp3` |
| `prod-ec2-k8s-worker-2b` | worker | `ap-northeast-2b` | `prod-subnet-private-2b` | `t3.medium` | `50GB gp3` |
| `prod-ec2-k8s-worker-2c` | worker | `ap-northeast-2c` | `prod-subnet-private-2c` | `t3.medium` | `50GB gp3` |

### 2.2 Track B 최종 상태

| 이름 | 역할 | AZ | 서브넷 | 타입 | 루트 디스크 |
| --- | --- | --- | --- | --- | --- |
| `prod-ec2-k8s-cp-2a` | control-plane | `ap-northeast-2a` | `prod-subnet-private-2a` | `t3.medium` | `50GB gp3` |
| `prod-ec2-k8s-cp-2b` | control-plane | `ap-northeast-2b` | `prod-subnet-private-2b` | `t3.medium` | `50GB gp3` |
| `prod-ec2-k8s-cp-2c` | control-plane | `ap-northeast-2c` | `prod-subnet-private-2c` | `t3.medium` | `50GB gp3` |
| `prod-ec2-k8s-worker-2a-1` | worker | `ap-northeast-2a` | `prod-subnet-private-2a` | `t3.medium` | `50GB gp3` |
| `prod-ec2-k8s-worker-2a-2` | worker | `ap-northeast-2a` | `prod-subnet-private-2a` | `t3.medium` | `50GB gp3` |
| `prod-ec2-k8s-worker-2b` | worker | `ap-northeast-2b` | `prod-subnet-private-2b` | `t3.medium` | `50GB gp3` |
| `prod-ec2-k8s-worker-2c` | worker | `ap-northeast-2c` | `prod-subnet-private-2c` | `t3.medium` | `50GB gp3` |

## 3. 네이밍 규칙

| 구분 | 이름 |
| --- | --- |
| internal API NLB | `prod-nlb-k8s-apiserver-int` |
| public ingress NLB | `prod-nlb-k8s-ingress-pub` |
| control-plane SG | `prod-sg-k8s-control-plane` |
| worker SG | `prod-sg-k8s-worker` |
| internal API NLB SG | `prod-sg-k8s-apiserver-nlb` |
| public ingress NLB SG | `prod-sg-k8s-ingress-nlb` |
| node IAM role | `prod-k8s-node-role` |
| node IAM profile | `prod-k8s-node-instance-profile` |
| etcd backup prefix | `s3://<BACKUP_BUCKET>/k8s/prod/` |

## 4. 실행 위치 약속

- `로컬 작업 PC`: Terraform 수정, `terraform plan/apply`, AWS CLI, kubectl 원격 접근 준비
- `control-plane`: `kubeadm init`, add-on 설치, `kubectl` 운영
- `worker`: `kubeadm join`, 노드 단위 점검
- `검증 PC`: `curl`, WebSocket handshake, Host 헤더 기반 외부 라우팅 점검

## Phase 0. 사전 준비

### Step 0-1. 현재 prod 상태 백업

- 실행 위치: `로컬 작업 PC`
- 목적: v2 기준값과 Terraform 상태를 백업하고, 롤백 기준점을 만든다.
- 명령어:

```bash
cd /Users/kimsj/kakao-tech/kall3team/3-team-Tasteam-cloud/v2-docker/terraform/environments/prod

terraform init
terraform state pull > "terraform-state-backup-$(date +%Y%m%d-%H%M%S).json"
terraform output > "terraform-output-backup-$(date +%Y%m%d-%H%M%S).txt"

terraform output -raw ec2_caddy_public_ip
terraform output -raw ec2_redis_private_ip
terraform output -raw rds_address
terraform output -raw cloud_map_service_dns
```

- 기대 결과:
  - state/outputs 백업 파일이 생성된다.
  - 현재 Caddy, Redis, RDS 엔드포인트가 확인된다.
- 실패 징후:
  - `terraform init` 실패
  - backend state 접근 실패
- 롤백 / 정리:
  - 변경 사항은 아직 없으므로 백업 파일만 남기고 종료한다.

### Step 0-2. 공용 ECR / 이미지 위치 확인

- 실행 위치: `로컬 작업 PC`
- 목적: Track A 에서 사용할 Spring/FastAPI 이미지 URI 를 확정한다.
- 명령어:

```bash
cd /Users/kimsj/kakao-tech/kall3team/3-team-Tasteam-cloud/v2-docker/terraform/environments/shared

terraform init
terraform output -raw ecr_repository_backend_url

echo "FASTAPI_IMAGE 는 AI 레포 CI 또는 별도 ECR에서 확인해서 수동 입력"
```

- 기대 결과:
  - Spring Boot ECR URI 를 확보한다.
  - FastAPI 이미지 URI 를 별도 준비한다.
- 실패 징후:
  - shared state 접근 실패
  - FastAPI 이미지 위치를 확인할 수 없음
- 롤백 / 정리:
  - 이미지 위치가 불명확하면 Phase 4 진입을 중단한다.

### Step 0-3. 백업 버킷 / 도구 준비

- 실행 위치: `로컬 작업 PC`
- 목적: 이후 백업과 설치 검증에 필요한 변수와 도구를 준비한다.
- 명령어:

```bash
export AWS_PROFILE=tasteam-v2
export AWS_REGION=ap-northeast-2
export BACKUP_BUCKET=$(
  cd /Users/kimsj/kakao-tech/kall3team/3-team-Tasteam-cloud/v2-docker/terraform/environments/prod && \
  terraform output -raw k8s_backup_bucket_name
)

aws sts get-caller-identity
aws s3 ls "s3://${BACKUP_BUCKET}" || true

brew install helm jq yq kubectx || true
```

- 기대 결과:
  - AWS 계정/리전이 정확하고, Helm/JQ/Kubectl 계열 도구가 준비된다.
- 실패 징후:
  - 잘못된 AWS 계정
  - 백업 버킷 미존재
- 롤백 / 정리:
  - 환경변수를 해제하고 올바른 프로파일로 다시 시작한다.

## Phase 1. `prod` Terraform 확장

### Step 1-1. `2b` subnet 추가

- 실행 위치: `로컬 작업 PC`
- 목적: 기존 `2a/2c` subnet 을 유지한 채 `2b` 를 추가한다.
- 명령어:

```hcl
# v2-docker/terraform/environments/prod/main.tf
module "vpc" {
  source = "../../modules/vpc"

  environment          = var.environment
  vpc_cidr             = "10.11.0.0/16"
  public_subnet_cidrs  = ["10.11.0.0/20", "10.11.16.0/20", "10.11.32.0/20"]
  private_subnet_cidrs = ["10.11.128.0/20", "10.11.144.0/20", "10.11.160.0/20"]
  availability_zones   = ["ap-northeast-2a", "ap-northeast-2c", "ap-northeast-2b"]
}
```

- 기대 결과:
  - 기존 `2a`, `2c` subnet 은 유지되고 `2b` pair 만 추가된다.
- 실패 징후:
  - 배열 순서를 `2a, 2b, 2c` 로 바꿔 기존 subnet 교체가 발생하려는 plan 이 보임
- 롤백 / 정리:
  - 배열 순서를 원복하고 다시 `terraform plan` 한다.

### Step 1-2. K8s 전용 리소스 설계 반영

- 실행 위치: `로컬 작업 PC`
- 목적: v2 리소스와 분리된 병렬 K8s 리소스를 추가한다.
- 작업 원칙:
  - `asg_spring`, `ec2_caddy`, `ec2_redis`, `rds` 는 그대로 둔다.
  - 새 파일 예시: `v2-docker/terraform/environments/prod/k8s_prod.tf`
  - 기존 `module.vpc.private_subnet_ids` 인덱스는 아래처럼 해석한다.

```hcl
locals {
  private_subnet_2a = module.vpc.private_subnet_ids[0]
  private_subnet_2c = module.vpc.private_subnet_ids[1]
  private_subnet_2b = module.vpc.private_subnet_ids[2]

  public_subnet_2a = module.vpc.public_subnet_ids[0]
  public_subnet_2c = module.vpc.public_subnet_ids[1]
  public_subnet_2b = module.vpc.public_subnet_ids[2]
}
```

- 추가해야 할 리소스:
  - `aws_iam_role.prod_k8s_node`, `aws_iam_instance_profile.prod_k8s_node`
  - `aws_security_group.k8s_control_plane`
  - `aws_security_group.k8s_worker`
  - `aws_security_group.k8s_apiserver_nlb`
  - `aws_security_group.k8s_ingress_nlb`
  - `aws_lb.k8s_apiserver_internal`
  - `aws_lb.k8s_ingress_public`
  - 각 NLB 의 target group / listener / attachment
  - `module.ec2_k8s_cp_2a`
  - `module.ec2_k8s_worker_2b`
  - `module.ec2_k8s_worker_2c`
  - Track B 용 `module.ec2_k8s_cp_2b`, `module.ec2_k8s_cp_2c`, `module.ec2_k8s_worker_2a_1`, `module.ec2_k8s_worker_2a_2`
- IAM 정책 최소 범위:
  - `AmazonSSMManagedInstanceCore`
  - `ecr:GetAuthorizationToken`, `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer`, `ecr:BatchCheckLayerAvailability`
  - `ssm:GetParameter*` for `/prod/tasteam/backend/*`, `/prod/tasteam/fastapi/*`, `/prod/tasteam/monitoring/*`
  - `kms:Decrypt`
  - analytics/uploads S3 read-write
- SG 최소 규칙:
  - baseline:
    - 모든 노드는 private subnet + SSM 접속 기준으로 운영한다.
    - break-glass SSH 를 별도로 열지 않는 한 `22/tcp` 는 기본 SG 에 넣지 않는다.
  - control-plane SG ingress:
    - `6443/tcp` from `k8s_apiserver_nlb`, `k8s_worker`
    - `2379-2380/tcp` from `k8s_control_plane`
    - `10250/tcp` from `k8s_control_plane`, `k8s_worker`
    - `10257/tcp` from `k8s_control_plane`
    - `10259/tcp` from `k8s_control_plane`
    - `4789/udp` from `k8s_control_plane`, `k8s_worker`
  - worker SG ingress:
    - `30080/tcp`, `30443/tcp` from `k8s_ingress_nlb`
    - `10250/tcp` from `k8s_control_plane`
    - `4789/udp` from `k8s_control_plane`, `k8s_worker`
  - RDS SG:
    - `5432/tcp` from `k8s_worker`
  - Redis SG:
    - `6379/tcp` from `k8s_worker`
  - SG egress:
    - 이번 런북은 기본 `all` 허용으로 두고, egress 축소는 후속 하드닝 단계에서 다룬다.
- NLB 설계:
  - internal API NLB:
    - scheme: internal
    - security group: `k8s_apiserver_nlb`
    - subnets: private `2a`, `2c`, `2b`
    - listener: `6443/TCP`
    - target group: control-plane instances `6443/TCP`
    - target type: `instance`
    - health check: `TCP:6443`
    - attachment:
      - Track A: `cp-2a`
      - Track B: `cp-2b`, `cp-2c`
  - public ingress NLB:
    - scheme: internet-facing
    - security group: `k8s_ingress_nlb`
    - subnets: public `2a`, `2c`, `2b`
    - listeners: `80/TCP`, `443/TCP`
    - target groups: worker instances `30080/TCP`, `30443/TCP`
    - target type: `instance`
    - health check: `TCP:30080`, `TCP:30443`
    - attachment:
      - Track A: `worker-2b`, `worker-2c`
      - Track B: `worker-2a-1`, `worker-2a-2`
- 인스턴스 설계:
  - 타입: `t3.medium`
  - 루트 디스크: `50GB gp3`
  - 서브넷:
    - Track A: `cp-2a`, `worker-2b`, `worker-2c`
    - Track B: `cp-2b`, `cp-2c`, `worker-2a-1`, `worker-2a-2`
  - 프로파일: `prod-k8s-node-instance-profile`
- Terraform output 계약:
  - Track A 즉시 사용:
    - `k8s_api_nlb_dns_name`
    - `k8s_ingress_nlb_dns_name`
    - `k8s_apiserver_tg_arn`
    - `k8s_ingress_http_tg_arn`
    - `k8s_ingress_https_tg_arn`
    - `k8s_cp_2a_instance_id`
    - `k8s_worker_2b_instance_id`
    - `k8s_worker_2c_instance_id`
  - Track B apply 후 사용:
    - `k8s_cp_2b_instance_id`
    - `k8s_cp_2c_instance_id`

- 기대 결과:
  - 새 K8s 자원만 추가되고 기존 v2 자원에는 diff 가 없어야 한다.
- 실패 징후:
  - `prod-sg-app`, `asg_spring`, 기존 subnet/resource replacement 가 plan 에 등장함
- 롤백 / 정리:
  - `k8s_prod.tf` 에서 새 리소스만 제거하고 다시 plan 한다.

### Step 1-3. Track A `plan/apply`

- 실행 위치: `로컬 작업 PC`
- 목적: Track A 에 필요한 네트워크 / IAM / NLB / 노드를 먼저 생성한다.
- 명령어:

```bash
cd /Users/kimsj/kakao-tech/kall3team/3-team-Tasteam-cloud/v2-docker/terraform/environments/prod

terraform fmt
terraform validate
terraform plan -out=tfplan-k8s-track-a
terraform show -no-color tfplan-k8s-track-a | tee tfplan-k8s-track-a.txt
terraform apply tfplan-k8s-track-a

# target registration 확인
aws elbv2 describe-target-health \
  --target-group-arn "$(terraform output -raw k8s_apiserver_tg_arn)"

aws elbv2 describe-target-health \
  --target-group-arn "$(terraform output -raw k8s_ingress_http_tg_arn)"

aws elbv2 describe-target-health \
  --target-group-arn "$(terraform output -raw k8s_ingress_https_tg_arn)"
```

- 기대 결과:
  - 새 `2b` subnet
  - Track A 노드 3대
  - internal/public NLB 와 target group
  - 새 IAM profile / SG
  - RDS/Redis SG 허용 규칙 추가
  - target group 에 Track A 인스턴스 attachment 가 보인다.
  - 이 시점의 health status 는 `initial` 또는 `unhealthy` 여도 괜찮다. API server 와 ingress 는 아직 기동 전이다.
- 실패 징후:
  - EC2 생성은 되었지만 SSM managed instance 로 올라오지 않음
  - target registration 자체가 비어 있음
- 롤백 / 정리:

```bash
terraform destroy \
  -target=module.ec2_k8s_cp_2a \
  -target=module.ec2_k8s_worker_2b \
  -target=module.ec2_k8s_worker_2c \
  -target=aws_lb.k8s_apiserver_internal \
  -target=aws_lb.k8s_ingress_public \
  -target=aws_security_group.k8s_control_plane \
  -target=aws_security_group.k8s_worker \
  -target=aws_security_group.k8s_apiserver_nlb \
  -target=aws_security_group.k8s_ingress_nlb
```

### Step 1-4. 신규 출력값 확인

- 실행 위치: `로컬 작업 PC`
- 목적: Phase 2/3 에서 사용할 대상 인스턴스와 NLB DNS 를 확인한다.
- 명령어:

```bash
terraform output

# 아래 출력은 k8s 리소스 추가 시 함께 만들어둔다.
terraform output -raw k8s_api_nlb_dns_name
terraform output -raw k8s_ingress_nlb_dns_name
terraform output -raw k8s_apiserver_tg_arn
terraform output -raw k8s_ingress_http_tg_arn
terraform output -raw k8s_ingress_https_tg_arn
terraform output -raw k8s_cp_2a_instance_id
terraform output -raw k8s_worker_2b_instance_id
terraform output -raw k8s_worker_2c_instance_id

# 아래 출력은 Track B apply 후 확인한다.
# Track A 시점에는 아직 값이 없어서 실패할 수 있다.
terraform output -raw k8s_cp_2b_instance_id
terraform output -raw k8s_cp_2c_instance_id
```

- 기대 결과:
  - API NLB DNS, ingress NLB DNS, target group ARN, Track A 인스턴스 ID 를 모두 확보한다.
  - Track B 시점에는 cp-2b/c 인스턴스 ID 도 같은 이름으로 조회된다.
- 실패 징후:
  - 필요한 output 이 없음
- 롤백 / 정리:
  - output block 을 추가하고 다시 `terraform apply` 한다.

## Phase 2. 모든 노드 공통 OS bootstrap

### Step 2-1. SSM 으로 Track A 노드 접속

- 실행 위치: `로컬 작업 PC`
- 목적: private subnet 노드에 SSH 없이 접속한다.
- 명령어:

```bash
export CP1_INSTANCE_ID=$(terraform output -raw k8s_cp_2a_instance_id)
export WK2B_INSTANCE_ID=$(terraform output -raw k8s_worker_2b_instance_id)
export WK2C_INSTANCE_ID=$(terraform output -raw k8s_worker_2c_instance_id)

aws ssm start-session --target "${CP1_INSTANCE_ID}"
aws ssm start-session --target "${WK2B_INSTANCE_ID}"
aws ssm start-session --target "${WK2C_INSTANCE_ID}"
```

- 기대 결과:
  - 세 노드 모두 shell 세션이 열린다.
- 실패 징후:
  - `TargetNotConnected`
- 롤백 / 정리:
  - IAM profile / SSM agent / outbound NAT 경로를 먼저 복구한다.

### Step 2-2. 노드 bootstrap 스크립트 실행

- 실행 위치: `각 노드`
- 목적: kubeadm 전 공통 OS 설정을 끝낸다.
- 명령어:

```bash
cat <<'EOF' >/tmp/bootstrap-k8s-node.sh
#!/usr/bin/env bash
set -euo pipefail

sudo hostnamectl set-hostname "${1:?hostname required}"
sudo timedatectl set-timezone Asia/Seoul
sudo timedatectl set-ntp true

sudo swapoff -a
sudo sed -i.bak '/ swap / s/^/#/' /etc/fstab

sudo apt-get update
sudo apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gettext-base \
  gnupg \
  jq \
  socat \
  conntrack \
  ebtables \
  ethtool \
  containerd

sudo mkdir -p /etc/modules-load.d /etc/sysctl.d /etc/containerd /etc/apt/keyrings
cat <<'MOD' | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
MOD

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<'SYS' | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
SYS

sudo sysctl --system
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl enable --now containerd

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
EOF

chmod +x /tmp/bootstrap-k8s-node.sh
sudo /tmp/bootstrap-k8s-node.sh prod-ec2-k8s-cp-2a
```

- worker 에서는 hostname 만 바꿔 실행:

```bash
sudo /tmp/bootstrap-k8s-node.sh prod-ec2-k8s-worker-2b
sudo /tmp/bootstrap-k8s-node.sh prod-ec2-k8s-worker-2c
```

- 기대 결과:
  - `containerd`, `kubelet`, `kubeadm`, `kubectl` 설치 완료
  - swap 비활성화
  - `SystemdCgroup = true`
- 실패 징후:
  - `swap is enabled`
  - `containerd` inactive
  - Kubernetes repo 추가 실패
- 롤백 / 정리:

```bash
sudo kubeadm reset -f || true
sudo apt-mark unhold kubelet kubeadm kubectl || true
sudo apt-get remove -y kubelet kubeadm kubectl containerd || true
sudo rm -f /etc/apt/sources.list.d/kubernetes.list
```

### Step 2-3. bootstrap 검증

- 실행 위치: `각 노드`
- 목적: kubeadm init/join 전에 공통 준비 상태를 확인한다.
- 명령어:

```bash
swapon --show
systemctl status containerd --no-pager
systemctl status kubelet --no-pager
sudo ctr version
hostnamectl
```

- 기대 결과:
  - swap 출력 없음
  - `containerd` active
  - `kubelet` active (또는 kubeadm 대기 상태)
- 실패 징후:
  - `container runtime is not running`
- 롤백 / 정리:
  - Step 2-2 를 다시 수행한다.

## Phase 3. Track A 클러스터 기동

### Step 3-1. 첫 control-plane 초기화

- 실행 위치: `prod-ec2-k8s-cp-2a`, `로컬 작업 PC`
- 목적: internal API NLB 를 endpoint 로 사용하는 첫 control-plane 을 띄운다.
- 명령어:

```bash
export K8S_API_NLB_DNS=<terraform output -raw k8s_api_nlb_dns_name>
export CP1_PRIVATE_IP=$(hostname -I | awk '{print $1}')

cat <<EOF >/tmp/kubeadm-init.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${CP1_PRIVATE_IP}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    - name: node-ip
      value: ${CP1_PRIVATE_IP}
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: stable-1.34
controlPlaneEndpoint: "${K8S_API_NLB_DNS}:6443"
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
apiServer:
  certSANs:
    - ${K8S_API_NLB_DNS}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
serverTLSBootstrap: true
EOF

sudo kubeadm init --config /tmp/kubeadm-init.yaml --upload-certs | tee /root/kubeadm-init.out

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown "$(id -u):$(id -g)" $HOME/.kube/config

kubeadm token create --ttl 2h --print-join-command | tee /root/join-worker.sh
CERT_KEY=$(sudo kubeadm init phase upload-certs --upload-certs | tail -1)
echo "$CERT_KEY" | tee /root/certificate-key.txt

echo "Track A worker join command:"
cat /root/join-worker.sh

# 로컬 kubectl 을 쓸 계획이면 admin.conf 내용을 안전한 로컬 파일로 복사해둔다.
sudo cat /etc/kubernetes/admin.conf

# 로컬 작업 PC에서 API target health 재확인
cd /Users/kimsj/kakao-tech/kall3team/3-team-Tasteam-cloud/v2-docker/terraform/environments/prod
aws elbv2 describe-target-health \
  --target-group-arn "$(terraform output -raw k8s_apiserver_tg_arn)"
```

- 기대 결과:
  - `/etc/kubernetes/admin.conf` 생성
  - `kubectl get nodes` 시 cp 노드 1대 확인
  - worker join command 와 certificate key 확보
  - API NLB target group 이 `healthy` 로 전환된다.
- 주의사항:
  - **v1beta4 kubeletExtraArgs 형식**: v1beta4 부터 `kubeletExtraArgs` 는 map 이 아닌 배열이다. `[{name: node-ip, value: <IP>}]` 형식을 사용해야 한다. map 형태(`{node-ip: <IP>}`)를 쓰면 `json: cannot unmarshal object into Go struct field` 에러가 발생한다.
  - **NLB 초기 접속 지연**: NLB target group 이 healthy 가 되기 전에 `controlPlaneEndpoint` 로 NLB DNS 를 사용하면 init 이 timeout 될 수 있다. 이 경우 `controlPlaneEndpoint` 를 CP private IP 로 직접 지정하고, NLB DNS 는 `certSANs` 에만 넣어 인증서에 포함시킨 뒤, 클러스터 안정화 후 kubeconfig 의 server 를 NLB DNS 로 교체할 수 있다.
  - **SSM 세션에서 kubectl 오류**: SSM 으로 `sudo su` 접속 시 `$HOME` 이 `/root` 가 아닐 수 있어 `~/.kube/config` 를 찾지 못한다. `export KUBECONFIG=/etc/kubernetes/admin.conf` 를 명시하거나 `/root/.kube/config` 로 복사한다.
  - **kubeadm reset 후 kubeconfig 갱신 필수**: `kubeadm reset` + 재 `init` 하면 새 CA 인증서가 생성된다. 기존 `~/.kube/config` 에 이전 CA 가 남아 `x509: certificate signed by unknown authority` 에러가 발생하므로 반드시 `cp /etc/kubernetes/admin.conf ~/.kube/config` 를 재실행해야 한다.
- 실패 징후:
  - `timed out waiting for the condition`
  - `controlPlaneEndpoint` 접근 실패
  - API target health 가 계속 `unhealthy`
  - `x509: certificate signed by unknown authority` — kubeconfig 미갱신
- 롤백 / 정리:

```bash
sudo kubeadm reset -f
sudo rm -rf $HOME/.kube /etc/cni/net.d
```

### Step 3-2. Track A worker join

- 실행 위치: `prod-ec2-k8s-worker-2b`, `prod-ec2-k8s-worker-2c`
- 목적: cp1 아래에 worker 2대를 붙인다.
- 명령어:

```bash
# cp-2a 에서 출력한 join command 를 그대로 복사해서 각 worker 에서 실행
sudo kubeadm join <K8S_API_NLB_DNS>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

- 기대 결과:
  - 두 worker 가 cluster 에 `Ready` 또는 `NotReady` 로 먼저 보이고, CNI 설치 후 `Ready` 로 전환된다.
- 실패 징후:
  - `discovery token ca cert hash` mismatch
  - `connection refused` to API endpoint
- 롤백 / 정리:

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
```

### Step 3-3. Calico 설치

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: AWS VPC 에서 동작 우선 기준으로 Calico `iptables + VXLAN CrossSubnet` 조합을 올린다.
- 비고:
  - `05-kubeadm.md` 는 Calico 선택까지 확정했지만 AWS VPC encapsulation 은 고정하지 않았다.
  - 이번 런북은 BGP 직접 라우팅 대신 **VXLAN CrossSubnet** 으로 시작한다.
- 명령어:

```bash
helm repo add projectcalico https://docs.tigera.io/calico/charts
helm repo update

kubectl create namespace tigera-operator --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install calico projectcalico/tigera-operator -n tigera-operator

cat <<'EOF' >/tmp/calico-installation.yaml
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - cidr: 10.244.0.0/16
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

kubectl apply -f /tmp/calico-installation.yaml
kubectl rollout status deployment/calico-kube-controllers -n calico-system --timeout=5m
kubectl get pods -n calico-system -o wide
```

- 기대 결과:
  - `calico-system` pod 들이 `Running`
  - `kubectl get nodes` 가 전부 `Ready`
- 주의사항:
  - **`kubernetesProvider: kubeadm` 사용 금지**: Calico Installation CRD 의 `spec.kubernetesProvider` 에 `kubeadm` 은 유효한 값이 아니다 (EKS, GKE, AKS 등만 허용). 넣으면 operator 가 `validation failed` 로 거부한다. kubeadm 환경에서는 이 필드를 생략한다.
  - **Security Group 포트 개방 필수**: Calico 가 정상 동작하려면 아래 포트가 노드 간 양방향 열려 있어야 한다. Terraform 에서 cp↔cp, cp↔worker, worker↔worker 방향 모두 추가한다.
    - **5473/tcp** (Typha): calico-node → Typha 통신. 미개방 시 `dial tcp <IP>:5473: i/o timeout` 에러와 함께 calico-node CrashLoopBackOff.
    - **179/tcp** (BGP): VXLANCrossSubnet 모드에서도 BGP peering 이 필요하다. 미개방 시 BGP 세션 수립 실패.
    - **4789/udp** (VXLAN): VXLAN 데이터 플레인 트래픽. 이미 기존 SG 에 있을 수 있으나 반드시 확인한다.
  - **CSR 수동 승인**: `serverTLSBootstrap: true` 사용 시 kubelet serving cert CSR 이 Pending 상태로 쌓인다. `kubectl get csr -o name | xargs kubectl certificate approve` 로 일괄 승인해야 노드가 완전히 Ready 로 전환된다.
  - **Worker NotReady + `cni plugin not initialized`**: CNI config 파일(`/etc/cni/net.d/10-calico.conflist`)과 바이너리(`/opt/cni/bin/calico`)가 존재하는데도 worker 가 NotReady 인 경우, containerd 가 CNI 설정을 인식하지 못한 것이다. `systemctl restart containerd && systemctl restart kubelet` 로 해결된다.
  - **CrashLoopBackOff 백오프 카운터 초기화**: 여러 번 init/reset 을 반복하면 containerd 에 이전 컨테이너의 restart 카운터가 남아 즉시 CrashLoopBackOff 에 빠질 수 있다. `crictl rmp -af && systemctl restart containerd && systemctl start kubelet` 로 카운터를 리셋한다.
- 실패 징후:
  - node 계속 `NotReady`
  - `BIRD is not ready` 류 메시지 반복
  - `dial tcp <IP>:5473: i/o timeout` — SG 5473 미개방
  - `cni plugin not initialized` — containerd 가 CNI 미인식
- 롤백 / 정리:

```bash
helm uninstall calico -n tigera-operator || true
kubectl delete installation.operator.tigera.io default || true
kubectl delete apiserver.operator.tigera.io default || true
```

### Step 3-4. Metrics Server 설치

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: HPA 에 필요한 리소스 메트릭을 제공한다.
- 명령어:

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system \
  --set args[0]=--kubelet-insecure-tls \
  --set args[1]=--kubelet-preferred-address-types=InternalIP,Hostname

kubectl rollout status deployment/metrics-server -n kube-system --timeout=5m
kubectl top nodes
```

- 기대 결과:
  - `kubectl top nodes` 가 값 반환
- 주의사항:
  - **Helm `--set` 콤마 이스케이프**: `--set args[1]=--kubelet-preferred-address-types=InternalIP,Hostname` 에서 콤마가 Helm 의 값 구분자로 해석된다. `InternalIP\,Hostname` 으로 이스케이프하거나 `--set-string` 을 사용한다.
- 실패 징후:
  - `Metrics API not available`
  - `key "Hostname" has no value` — 콤마 미이스케이프
- 롤백 / 정리:

```bash
helm uninstall metrics-server -n kube-system
```

### Step 3-5. ingress-nginx 설치

- 실행 위치: `prod-ec2-k8s-cp-2a`, `로컬 작업 PC`
- 목적: public NLB 가 바라볼 NodePort ingress 를 설치한다.
- 명령어:

```bash
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.replicaCount=2 \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.admissionWebhooks.enabled=true

kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=5m
kubectl get svc -n ingress-nginx ingress-nginx-controller

# 로컬 작업 PC에서 ingress target health 재확인
cd /Users/kimsj/kakao-tech/kall3team/3-team-Tasteam-cloud/v2-docker/terraform/environments/prod
aws elbv2 describe-target-health \
  --target-group-arn "$(terraform output -raw k8s_ingress_http_tg_arn)"

aws elbv2 describe-target-health \
  --target-group-arn "$(terraform output -raw k8s_ingress_https_tg_arn)"
```

- 기대 결과:
  - ingress-nginx controller 2개가 worker 에 올라간다.
  - service 가 `NodePort 30080/30443` 로 노출된다.
  - public NLB target group health 가 점차 `healthy` 로 바뀐다.
- 실패 징후:
  - controller pod 가 control-plane 에 붙으려 함
  - public NLB target unhealthy 지속
- 롤백 / 정리:

```bash
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx
```

### Step 3-6. Linkerd 설치

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: `app-prod` 에 mTLS / retry / timeout 관측 기반을 제공한다.
- 명령어:

```bash
# SSM 세션에서는 HOME이 설정되지 않을 수 있으므로 명시적으로 지정
export HOME=/root
export KUBECONFIG=$HOME/.kube/config

# Gateway API CRDs 설치 (Linkerd 전제 조건)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

# Linkerd CLI 설치
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
export PATH="$HOME/.linkerd2/bin:$PATH"

linkerd check --pre
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check
```

- 기대 결과:
  - `linkerd check` 통과
- 실패 징후:
  - `HOME` 미설정 시 Linkerd CLI 설치 경로 오류 — `export HOME=/root` 확인
  - Gateway API CRDs 미설치 시 `linkerd install` 실패
  - CNI / iptables / admission webhook 관련 pre-check 실패
- 롤백 / 정리:

```bash
linkerd uninstall | kubectl delete -f - || true
kubectl delete namespace linkerd || true
```

### Step 3-6-1. ECR Credential Provider 설정

- 실행 위치: **모든 노드** (cp + worker)
- 목적: kubelet 이 IAM Role 기반으로 ECR 이미지를 pull 할 수 있도록 credential provider 를 설정한다.
- 전제: EC2 에 `ecr:GetAuthorizationToken`, `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` 권한이 포함된 IAM Role 이 연결되어 있어야 한다.
- 명령어 (노드별 SSM 접속 후 실행):

```bash
# 바이너리 설치
sudo mkdir -p /usr/local/bin/ecr-credential-provider
curl -Lo /tmp/ecr-credential-provider \
  https://artifacts.k8s.io/binaries/cloud-provider-aws/v1.31.7/linux/amd64/ecr-credential-provider-linux-amd64
sudo install -m 755 /tmp/ecr-credential-provider \
  /usr/local/bin/ecr-credential-provider/ecr-credential-provider

# 바이너리 확인 — ELF 64-bit 이어야 정상
file /usr/local/bin/ecr-credential-provider/ecr-credential-provider

# credential provider 설정 파일 생성
sudo tee /etc/kubernetes/credential-provider.yaml > /dev/null << 'EOF'
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
providers:
  - name: ecr-credential-provider
    matchImages:
      - "*.dkr.ecr.*.amazonaws.com"
    defaultCacheDuration: "12h"
    apiVersion: credentialprovider.kubelet.k8s.io/v1
EOF

# kubelet 에 플래그 추가 (/etc/default/kubelet → 드롭인의 KUBELET_EXTRA_ARGS 로 참조됨)
echo 'KUBELET_EXTRA_ARGS=--image-credential-provider-config=/etc/kubernetes/credential-provider.yaml --image-credential-provider-bin-dir=/usr/local/bin/ecr-credential-provider' \
  | sudo tee /etc/default/kubelet

# kubelet 재시작
sudo systemctl restart kubelet

# 적용 확인 — 프로세스 인자에 credential-provider 가 포함되어야 함
ps aux | grep kubelet | grep credential
```

- 기대 결과:
  - kubelet 프로세스에 `--image-credential-provider-config`, `--image-credential-provider-bin-dir` 플래그 확인
  - ECR 이미지 pull 시 `no basic auth credentials` 에러 없음
- 실패 징후:
  - `file` 명령 결과가 `XML` 이면 바이너리 다운로드 실패 — URL/버전 확인
  - kubelet 로그에 `unknown field "imageCredentialProvider..."` → config.yaml 이 아닌 `/etc/default/kubelet` 에 CLI 플래그로 넣어야 함
- 롤백 / 정리:

```bash
sudo rm /etc/default/kubelet
sudo rm /etc/kubernetes/credential-provider.yaml
sudo rm -rf /usr/local/bin/ecr-credential-provider
sudo systemctl restart kubelet
```

### Step 3-7. ArgoCD 설치

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: 이후 GitOps 운영용 control plane 을 먼저 올린다.
- 명령어:

```bash
# Helm repo 추가
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# argocd.yaml 을 cloud-repo 에서 가져오거나, /tmp 에 작성
# 원본: v3-k8s/manifests/helm/values/argocd.yaml
# Helm 설치
helm install argocd argo/argo-cd -n argocd --create-namespace -f /tmp/argocd.yaml

# 롤아웃 대기
kubectl rollout status deployment/argocd-server -n argocd --timeout=10m
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=10m

# 초기 admin 비밀번호 확인
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

- 기대 결과:
  - `argocd` namespace 핵심 컴포넌트가 `Running`
  - Helm values 에 설정한 Ingress, 리소스 제한, cloud-repo 연결이 반영됨
- 실패 징후:
  - CRD apply 실패 — ArgoCD CRD가 크므로 client-side apply 시 annotation 262KB 초과 에러 가능. 이 경우 `kubectl apply --server-side --force-conflicts` 사용
  - Helm values YAML 파싱 오류
  - 이전 ArgoCD 잔여 리소스가 있는 경우 selector immutable 에러 — `kubectl delete deploy,sts,svc,networkpolicy --all -n argocd` 후 재적용
- 롤백 / 정리:

```bash
helm uninstall argocd -n argocd
kubectl delete namespace argocd
```

### Step 3-8. External Secrets Operator (ESO) 설치

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: AWS SSM Parameter Store에 저장된 기존 민감값을 그대로 재사용하기 위해 ESO를 설치한다. ESO는 ExternalSecret 리소스를 감지해 SSM 값을 Kubernetes Secret으로 자동 동기화한다. EC2 노드의 IAM 인스턴스 프로파일을 통해 SSM 접근 권한을 획득한다.
- 명령어:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --set installCRDs=true

kubectl rollout status deployment/external-secrets -n external-secrets --timeout=5m
kubectl get deployment -n external-secrets
```

- 기대 결과:
  - `external-secrets`, `external-secrets-cert-controller`, `external-secrets-webhook` pod `Running`
- 실패 징후:
  - deployment 가 생성되지 않음
  - CRD 설치 실패 (`kubectl get crd | grep external-secrets.io` 로 확인)
- 롤백 / 정리:
  - `helm uninstall external-secrets -n external-secrets`
  - `kubectl delete namespace external-secrets`

### Step 3-8-1. ClusterSecretStore 생성 (수동 관리)

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: ESO 가 AWS Parameter Store 에 접근할 수 있도록 ClusterSecretStore 를 생성한다.
- 전제: 노드 IAM Role 에 `ssm:GetParameter*` 권한이 이미 포함되어 있다 (Step 1-2 IAM 정책 참고).
- 비고: ClusterSecretStore 는 cluster-scoped 인프라 리소스이므로 ArgoCD GitOps 대상이 아닌 **수동 관리** 로 운영한다. 한번 생성하면 변경할 일이 거의 없다.
- 명령어:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-parameter-store
spec:
  provider:
    aws:
      service: ParameterStore
      region: ap-northeast-2
EOF

kubectl get clustersecretstore aws-parameter-store
```

- 기대 결과:
  - ClusterSecretStore `aws-parameter-store` 가 `Valid` / `Ready: True` 상태
- 실패 징후:
  - IAM 권한 부족으로 `SecretStore is not ready`
  - ESO controller 가 아직 Running 이 아닌 경우
- 롤백 / 정리:
  - `kubectl delete clustersecretstore aws-parameter-store` 후 IAM 권한 / ESO 상태를 점검한다.

### Step 3-8-2. Track A addon 상태 / 버전 캡처

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: Track B 와 이후 재설치 시 Track A 에서 검증된 chart/image 조합을 기준으로 재현한다.
- 명령어:

```bash
helm list -A | tee /root/track-a-helm-releases.txt

kubectl get deployment,statefulset -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,KIND:.kind,NAME:.metadata.name,IMAGES:.spec.template.spec.containers[*].image' \
  | tee /root/track-a-addon-images.txt

kubectl get clustersecretstore -o yaml | tee /root/track-a-eso-config.txt
```

- 기대 결과:
  - Helm release 목록, 핵심 addon 이미지 목록, ESO ClusterSecretStore 설정이 파일로 남는다.
- 실패 징후:
  - `helm list -A` 실패
  - 이미지 목록 추출 실패
- 롤백 / 정리:
  - `/root/track-a-helm-releases.txt`, `/root/track-a-addon-images.txt`, `/root/track-a-eso-config.txt` 를 삭제하고 다시 캡처한다.

### Step 3-9. 초기 백업

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: Track A 직후 etcd snapshot 을 백업한다.
- 비고: ESO 는 Parameter Store 에서 값을 동기화하므로 별도 키 백업이 불필요하다. etcd 만 백업한다.
- 명령어:

```bash
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-track-a.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

sudo ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-track-a.db --write-out=table
aws s3 cp /tmp/etcd-track-a.db \
  "s3://${BACKUP_BUCKET}/k8s/prod/etcd/etcd-track-a.db" \
  --sse aws:kms
```

- 기대 결과:
  - etcd snapshot 이 S3 에 저장된다.
- 실패 징후:
  - S3 업로드 실패
  - etcdctl TLS 오류
- 롤백 / 정리:
  - 백업이 실패하면 Track A 완료로 간주하지 않는다.

## Phase 4. `app-prod` 배포

### Step 4-1. namespace / Linkerd 자동 주입 준비

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: `app-prod` namespace 와 sidecar 주입을 먼저 준비한다.
- 명령어:

```bash
kubectl create namespace app-prod --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace app-prod linkerd.io/inject=enabled --overwrite
kubectl get namespace app-prod --show-labels
```

- 기대 결과:
  - `app-prod` 생성
  - `linkerd.io/inject=enabled`
- 실패 징후:
  - namespace 미생성
- 롤백 / 정리:

```bash
kubectl delete namespace app-prod
```

### Step 4-2. (생략 — ESO 가 대체)

- ESO(Step 3-8) + ExternalSecret(Step 4-3) 이 Parameter Store 값을 K8s Secret 으로 자동 동기화한다.
- 수동으로 env 파일을 추출할 필요 없음.

### Step 4-3. ExternalSecret 생성 (ArgoCD 관리)

- 실행 위치: cloud-repo `v3-k8s/manifests/app/overlays/prod/external-secret.yaml` 에 정의
- 목적: Parameter Store 의 민감값을 K8s Secret 으로 자동 동기화한다.
- 비고: ExternalSecret 은 namespace-scoped 이므로 ArgoCD GitOps 로 관리한다. `overlays/prod/kustomization.yaml` 의 resources 에 포함되어 있어 ArgoCD Sync 시 자동 적용된다.
- 주의: Parameter Store 키가 `/prod/tasteam/backend/DB_URL` 처럼 개별 경로이므로 `extract` 가 아닌 `find` + `rewrite` 를 사용해야 한다.
  - `find` 는 하위 경로를 탐색하여 모든 키를 수집
  - `rewrite` 는 경로 prefix 를 제거하여 Secret 키 이름을 정리 (예: `/prod/tasteam/backend/DB_URL` → `DB_URL`)
- 명령어:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: spring-boot-runtime
  namespace: app-prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: spring-boot-runtime
    creationPolicy: Owner
  dataFrom:
    - find:
        path: /prod/tasteam/backend
        name:
          regexp: ".*"
      rewrite:
        - regexp:
            source: "/prod/tasteam/backend/(.*)"
            target: "$1"
EOF

# FastAPI ExternalSecret — BE 파이프라인 검증 후 활성화
# cat <<'EOF' | kubectl apply -f -
# apiVersion: external-secrets.io/v1
# kind: ExternalSecret
# metadata:
#   name: fastapi-runtime
#   namespace: app-prod
# spec:
#   refreshInterval: 1h
#   secretStoreRef:
#     name: aws-parameter-store
#     kind: ClusterSecretStore
#   target:
#     name: fastapi-runtime
#     creationPolicy: Owner
#   dataFrom:
#     - find:
#         path: /prod/tasteam/fastapi
#         name:
#           regexp: ".*"
#       rewrite:
#         - regexp:
#             source: "/prod/tasteam/fastapi/(.*)"
#             target: "$1"
# EOF

kubectl get externalsecret -n app-prod
kubectl get secret spring-boot-runtime -n app-prod
```

- 기대 결과:
  - ExternalSecret `SecretSynced`, Secret 에 `DB_URL`, `JWT_SECRET` 등 키 이름으로 저장
- 실패 징후:
  - `SecretSyncedError` + `invalid secret keys` → rewrite source 패턴과 실제 경로 불일치
  - `Secret does not exist` → Parameter Store 경로 확인
  - IAM 권한 부족: `ssm:GetParametersByPath`, `ssm:DescribeParameters`, `kms:Decrypt` 필요
- 롤백 / 정리:
  - `kubectl delete externalsecret spring-boot-runtime -n app-prod`
  - ExternalSecret 삭제 시 `creationPolicy: Owner` 이므로 연결된 Secret도 함께 삭제된다.

### Step 4-4. ArgoCD GitOps 로 `app-prod` 배포

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: ArgoCD Application 이 cloud-repo 의 Kustomize 매니페스트를 Sync 하여 워크로드를 배포한다.
- 전제:
  - cloud-repo `v3-k8s/manifests/app/base/` 에 Deployment, Service, HPA, PDB, Ingress, NetworkPolicy 정의
  - cloud-repo `v3-k8s/manifests/app/overlays/prod/` 에서 환경별 오버라이드 (replicas, 이미지 태그, 도메인 등)
  - ArgoCD Application `tasteam-prod` 가 `overlays/prod` 를 감시하도록 등록 (Step 3-7 이후)
  - CD 워크플로우 (`backend-cd-v3.yml`) 가 main push 시 overlays/prod 의 이미지 태그를 자동 업데이트
- 배포 흐름:
  1. BE repo main push → GitHub Actions → Docker 빌드 → ECR push
  2. cloud-repo `overlays/prod/kustomization.yaml` 이미지 태그 업데이트 (bot commit)
  3. ArgoCD 가 변경 감지 → Sync (수동 Sync 설정이면 아래 명령 실행)
- 명령어:

```bash
# ArgoCD Application 상태 확인
kubectl get app tasteam-prod -n argocd

# OutOfSync 이면 수동 Sync 실행
kubectl patch app tasteam-prod -n argocd --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD","syncStrategy":{"apply":{"force":false}}}}}'

# 롤아웃 확인
kubectl rollout status deployment/spring-boot -n app-prod --timeout=10m
kubectl get pods -n app-prod -o wide
kubectl get ingress -n app-prod
kubectl get hpa -n app-prod
```

- 기대 결과:
  - `spring-boot` Pod 2개 `1/1 Running`
  - Ingress, Service, HPA, PDB 모두 정상 생성
- 실패 징후:
  - `ImagePullBackOff` → ECR credential provider 확인 (Step 3-6-1)
  - `CrashLoopBackOff` → ExternalSecret 동기화 상태 확인 (Step 4-3)
  - ArgoCD `Unknown` → cloud-repo 에 매니페스트 미반영
- 롤백 / 정리:
  - `kubectl rollout undo deployment/spring-boot -n app-prod`
  - 또는 cloud-repo 이미지 태그를 이전 버전으로 되돌린 뒤 ArgoCD 재 Sync

### Step 4-5. 내부 / 외부 smoke test

- 실행 위치: `prod-ec2-k8s-cp-2a` 및 `검증 PC`
- 목적: 절체 전 public NLB DNS 와 Host 헤더로 외부 라우팅을 검증한다.
- 명령어:

```bash
# 외부 의존성 reachability 확인 — ESO 가 동기화한 Secret 에서 값을 추출
DB_HOST=$(
  kubectl get secret spring-boot-runtime -n app-prod \
    -o jsonpath='{.data.DB_URL}' | base64 -d \
    | sed -E 's#^jdbc:postgresql://([^:/?]+).*#\1#'
)
REDIS_HOST=$(
  kubectl get secret spring-boot-runtime -n app-prod \
    -o jsonpath='{.data.REDIS_HOST}' | base64 -d
)
REDIS_PORT=$(
  kubectl get secret spring-boot-runtime -n app-prod \
    -o jsonpath='{.data.REDIS_PORT}' | base64 -d
)

kubectl run netcheck -n app-prod --rm -it --restart=Never \
  --image=nicolaka/netshoot \
  -- sh -lc "nc -vz ${DB_HOST} 5432 && nc -vz ${REDIS_HOST} ${REDIS_PORT}"

# 내부 서비스 확인용 임시 curl pod
kubectl run curlbox -n app-prod --rm -it --restart=Never \
  --image=curlimages/curl:8.12.1 \
  -- sh -c 'curl -fsS http://fastapi-svc/health && echo && curl -fsS http://spring-boot-svc/actuator/health'

# 외부 라우팅 확인
export PUBLIC_NLB_DNS=<terraform output -raw k8s_ingress_nlb_dns_name>

curl -i -H 'Host: tasteam.kr' "http://${PUBLIC_NLB_DNS}/api/actuator/health"
curl -i -H 'Host: tasteam.kr' "http://${PUBLIC_NLB_DNS}/ai/health"

# WebSocket handshake 확인 (경로는 실제 앱 엔드포인트로 교체)
curl -i --http1.1 \
  -H 'Host: tasteam.kr' \
  -H 'Connection: Upgrade' \
  -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==' \
  -H 'Sec-WebSocket-Version: 13' \
  "http://${PUBLIC_NLB_DNS}/ws"
```

- 기대 결과:
  - DB `5432`, Redis `6379` TCP reachability 통과
  - `/api/actuator/health` 200
  - `/ai/health` 200
  - `/ws` 는 실제 앱 계약에 따라 `101` 또는 인증/경로 관련 비-5xx 응답
- 실패 징후:
  - DB/Redis `nc` 실패
  - public NLB 5xx
  - ingress timeout
  - WebSocket upgrade 자체가 실패
- 롤백 / 정리:
  - SSM env 추출값, RDS/Redis SG 규칙, Ingress, Service, worker target group 등록 상태를 먼저 확인한다.

## Phase 5. Track B 운영 확장

### Step 5-1. Track B 노드 생성

- 실행 위치: `로컬 작업 PC`
- 목적: control-plane 2대와 worker 2대를 추가한다.
- 명령어:

```bash
cd /Users/kimsj/kakao-tech/kall3team/3-team-Tasteam-cloud/v2-docker/terraform/environments/prod

terraform plan -out=tfplan-k8s-track-b
terraform apply tfplan-k8s-track-b
```

- Track B 추가 대상:
  - `prod-ec2-k8s-cp-2b`
  - `prod-ec2-k8s-cp-2c`
  - `prod-ec2-k8s-worker-2a-1`
  - `prod-ec2-k8s-worker-2a-2`

- 기대 결과:
  - final topology 로 필요한 4대가 추가 생성
  - NLB target registration 범위가 final 상태로 확장
- 실패 징후:
  - 새 인스턴스만 `unhealthy`
- 롤백 / 정리:
  - 새 Track B 자원만 target destroy 한다.

### Step 5-2. Track B 노드 bootstrap

- 실행 위치: `각 신규 노드`
- 목적: Track A 와 동일한 bootstrap 을 적용한다.
- 명령어:

```bash
# Step 2-2의 heredoc 전체를 신규 노드에 다시 붙여넣어 /tmp/bootstrap-k8s-node.sh 를 재생성한다.
# /tmp/bootstrap-k8s-node.sh 가 남아있다고 가정하지 않는다.
sudo /tmp/bootstrap-k8s-node.sh prod-ec2-k8s-cp-2b
sudo /tmp/bootstrap-k8s-node.sh prod-ec2-k8s-cp-2c
sudo /tmp/bootstrap-k8s-node.sh prod-ec2-k8s-worker-2a-1
sudo /tmp/bootstrap-k8s-node.sh prod-ec2-k8s-worker-2a-2
```

- 이후 **각 신규 노드에서 Step 3-6-1 (ECR Credential Provider 설정)** 을 동일하게 수행한다.
  - 바이너리 설치, `credential-provider.yaml` 생성, `/etc/default/kubelet` 플래그 추가, kubelet 재시작
  - 이 단계를 빠뜨리면 ECR 이미지 pull 시 `no basic auth credentials` 에러 발생

- 기대 결과:
  - 신규 4대 모두 kubeadm join 준비 완료
  - ECR credential provider 가 kubelet 에 설정됨
- 실패 징후:
  - containerd/kubelet inactive
  - `ps aux | grep kubelet | grep credential` 에 credential-provider 플래그 미확인
- 롤백 / 정리:
  - Step 2-2 rollback 과 동일

### Step 5-3. control-plane / worker join

- 실행 위치: `prod-ec2-k8s-cp-2a` 및 신규 노드
- 목적: control-plane 3대, worker 4대 완성
- 명령어:

```bash
# cp-2a 에서
JOIN_WORKER_CMD=$(kubeadm token create --ttl 2h --print-join-command)
CERT_KEY=$(sudo kubeadm init phase upload-certs --upload-certs | tail -1)

echo "${JOIN_WORKER_CMD}" | tee /root/join-worker-track-b.sh
echo "${JOIN_WORKER_CMD} --control-plane --certificate-key ${CERT_KEY}" \
  | tee /root/join-control-plane-track-b.sh

echo "Track B control-plane join command:"
cat /root/join-control-plane-track-b.sh
echo "Track B worker join command:"
cat /root/join-worker-track-b.sh
```

- 신규 control-plane 에서:

```bash
# cp-2a 에서 출력한 command 를 그대로 복사해서 각 신규 control-plane 에서 실행
sudo kubeadm join <K8S_API_NLB_DNS>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <CERT_KEY>
```

- 신규 worker 에서:

```bash
# cp-2a 에서 출력한 worker join command 를 그대로 복사해서 각 신규 worker 에서 실행
sudo kubeadm join <K8S_API_NLB_DNS>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

- 이후 확인:

```bash
# CSR 승인 (serverTLSBootstrap: true 사용 시 필수)
kubectl get csr
kubectl get csr -o name | xargs kubectl certificate approve

kubectl get nodes -o wide
kubectl get pods -A -o wide
```

- 기대 결과:
  - control-plane 3대, worker 4대 모두 `Ready`
  - final worker 분포 `2a x2, 2b x1, 2c x1`
- 실패 징후:
  - control-plane join 시 cert key 오류
  - etcd member sync 실패
  - 노드가 `NotReady` 지속 → CSR 승인 누락 확인 (`kubectl get csr`)
- 롤백 / 정리:

```bash
sudo kubeadm reset -f
```

## Phase 6. 운영 드릴

### Step 6-1. rollout 실패 / undo 확인

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: 배포 실패 시 `rollout undo` 경로를 검증한다.
- 명령어:

```bash
kubectl rollout status deployment/spring-boot -n app-prod
kubectl logs -l app=spring-boot -n app-prod --tail=50
kubectl describe pod -l app=spring-boot -n app-prod | grep -A5 "Events"

# 실제 실패 상황 대응
kubectl rollout undo deployment/spring-boot -n app-prod
kubectl rollout status deployment/spring-boot -n app-prod
```

- 기대 결과:
  - 실패 감지와 undo 경로가 확인된다.
- 실패 징후:
  - undo 후에도 Ready 복구 실패
- 롤백 / 정리:
  - Git / manifest 이미지 태그를 직전 버전으로 되돌린다.

### Step 6-2. worker drain / reschedule

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: worker 1대 유지보수 시 서비스가 유지되는지 확인한다.
- 명령어:

```bash
kubectl drain prod-ec2-k8s-worker-2b \
  --ignore-daemonsets \
  --delete-emptydir-data

kubectl get pods -n app-prod -o wide
kubectl uncordon prod-ec2-k8s-worker-2b
```

- 기대 결과:
  - Spring/FastAPI 가 다른 worker 로 재스케줄
  - 서비스 중단 없음
- 실패 징후:
  - PDB 때문에 drain 이 영원히 대기
  - pod 재스케줄 실패
- 롤백 / 정리:
  - 즉시 `uncordon` 하고 원인 분석 후 재시도한다.

### Step 6-3. control-plane 1대 실제 중단 / 복구 드릴

- 실행 위치: `로컬 작업 PC`, `prod-ec2-k8s-cp-2a`
- 목적: cp 1대 장애 시에도 API endpoint 가 유지되는지 확인한다.
- 명령어:

```bash
cd /Users/kimsj/kakao-tech/kall3team/3-team-Tasteam-cloud/v2-docker/terraform/environments/prod
export CP2B_INSTANCE_ID=$(terraform output -raw k8s_cp_2b_instance_id)

# 아래 2줄은 로컬 작업 PC에서 실행
aws ec2 stop-instances --instance-ids "${CP2B_INSTANCE_ID}"
aws ec2 wait instance-stopped --instance-ids "${CP2B_INSTANCE_ID}"

# 아래 3줄은 cp-2a 또는 KUBECONFIG 가 준비된 로컬에서 실행
kubectl get nodes
kubectl get pods -A
kubectl cluster-info

# 아래 2줄은 다시 로컬 작업 PC에서 실행
aws ec2 start-instances --instance-ids "${CP2B_INSTANCE_ID}"
aws ec2 wait instance-status-ok --instance-ids "${CP2B_INSTANCE_ID}"

# 아래 1줄은 cp-2a 또는 KUBECONFIG 가 준비된 로컬에서 실행
kubectl wait --for=condition=Ready node/prod-ec2-k8s-cp-2b --timeout=10m
```

- 기대 결과:
  - 나머지 2대가 quorum 유지
  - `kubectl` 동작 지속
  - `prod-ec2-k8s-cp-2b` 가 복구 후 다시 `Ready`
- 실패 징후:
  - API endpoint 불가
  - 재기동 후 node 가 `NotReady` 에서 복귀하지 않음
- 롤백 / 정리:
  - `aws ec2 start-instances --instance-ids "${CP2B_INSTANCE_ID}"` 를 다시 실행한 뒤 etcd / apiserver 로그를 확인한다.

### Step 6-4. HPA scale-out 확인

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: CPU 기반 HPA 가 실제로 pod 수를 늘리는지 검증한다.
- 명령어:

```bash
kubectl run loadgen -n app-prod --rm -it --restart=Never \
  --image=rakyll/hey \
  -- -z 120s -c 40 http://spring-boot-svc/actuator/health

kubectl get hpa -n app-prod -w
kubectl top pods -n app-prod
```

- 기대 결과:
  - `spring-boot-hpa` 가 `2 -> 3` 이상으로 상승
- 실패 징후:
  - metrics 값 없음
- 롤백 / 정리:
  - loadgen pod 종료 후 HPA 가 다시 안정화되는지 확인한다.

### Step 6-5. WebSocket idle / heartbeat 검증

- 실행 위치: `검증 PC`
- 목적: `/ws` ingress timeout 과 NLB chain 이 유휴 연결을 너무 빨리 끊지 않는지 본다.
- 명령어:

```bash
export PUBLIC_NLB_DNS=<terraform output -raw k8s_ingress_nlb_dns_name>

curl -i --http1.1 \
  -H 'Host: tasteam.kr' \
  -H 'Connection: Upgrade' \
  -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==' \
  -H 'Sec-WebSocket-Version: 13' \
  "http://${PUBLIC_NLB_DNS}/ws"
```

- 기대 결과:
  - handshake 가 성립하거나 최소한 ingress/backend 측 5xx 없이 응답
  - 실제 애플리케이션 heartbeat 주기가 Cloudflare 100초, NLB 350초보다 짧게 설정되어 있어야 한다.
- 실패 징후:
  - 짧은 시간 내 connection reset
- 롤백 / 정리:
  - `/ws` ingress annotation, 앱 heartbeat 주기, NLB listener 대상 포트를 다시 점검한다.

### Step 6-6. etcd backup 검증

- 실행 위치: `prod-ec2-k8s-cp-2a`
- 목적: snapshot 파일이 실제로 유효한지 확인한다.
- 명령어:

```bash
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-verify.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

sudo ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-verify.db --write-out=table
aws s3 cp /tmp/etcd-verify.db \
  "s3://${BACKUP_BUCKET}/k8s/prod/etcd/etcd-verify.db" \
  --sse aws:kms
```

- 기대 결과:
  - snapshot status table 출력
  - S3 업로드 성공
- 실패 징후:
  - status 출력 실패
- 롤백 / 정리:
  - cp 노드 디스크와 TLS cert 경로를 점검한다.

## 5. 완료 기준

### Track A 완료 기준

- `kubectl get nodes` 가 `cp1 + worker2` 모두 `Ready`
- API NLB target group 이 `healthy`
- ingress NLB `30080/30443` target group 이 `healthy`
- Calico / Metrics Server / ingress-nginx / Linkerd / ArgoCD / External Secrets Operator 모두 정상
- `app-prod` Spring/FastAPI health check 성공
- DB `5432`, Redis `6379` reachability 확인
- `/api`, `/ai` ingress 라우팅 성공
- `/ws` handshake 또는 비-5xx 응답 확인
- HPA 메트릭 조회 성공
- etcd snapshot 백업 성공

### Track B 완료 기준

- control-plane 3대가 internal API NLB 뒤에서 정상 동작
- worker 4대 분포가 `2a x2, 2b x1, 2c x1`
- worker 1대 drain 시 서비스 유지
- control-plane 1대 중단 시에도 `kubectl` 지속 가능
- 중단했던 control-plane node 가 복구 후 다시 `Ready`
- etcd snapshot 생성 및 업로드 성공

## 6. 이번에 하지 않는 것

- Cloudflare origin 전환
- v2 `tasteam.kr` 실트래픽 절체
- shared monitoring stack 이전
- `app-dev`, `app-stg` namespace 운영화
- IRSA / Cluster Autoscaler / monitoring PVC 고도화

## 7. 부록: 자주 막히는 포인트

- `2b` subnet 추가 시 배열 재정렬 금지
- `private_subnet_ids[1]` 는 `2c`, `private_subnet_ids[2]` 가 `2b`
- 새 worker SG 를 RDS/Redis SG 에 추가하지 않으면 앱이 뜨더라도 DB/Redis 연결 실패
- public NLB 는 `30080/30443`, internal API NLB 는 `6443` 로 target attachment 를 맞춰야 한다
- `http_put_response_hop_limit = 2` 를 낮추면 pod 내부 AWS SDK 자격증명 조회가 깨질 수 있다
- Track A 는 리허설이다. Cloudflare 나 기존 Caddy 라우팅은 건드리지 않는다

## 8. 공식 문서 참고

- Kubernetes kubeadm 설치: <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/>
- Kubernetes HA control plane 개요: <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/>
- Calico 설치 문서: <https://docs.tigera.io/calico/latest/getting-started/kubernetes/>
- ingress-nginx 문서: <https://kubernetes.github.io/ingress-nginx/>
- Metrics Server 문서: <https://github.com/kubernetes-sigs/metrics-server>
- Linkerd 설치 문서: <https://linkerd.io/2-edge/getting-started/>
- ArgoCD 설치 문서: <https://argo-cd.readthedocs.io/en/stable/getting_started/>
- External Secrets Operator 문서: <https://external-secrets.io/>
