# Track B control-plane join 트러블슈팅

- 날짜: 2026-03-21
- 범위: Phase 5 (Track B 운영 확장) — cp-2b, cp-2c join + worker-2a-1, worker-2a-2 join

## 문제 1: controlPlaneEndpoint 직접 IP 설정

### 증상
- cp-2b join 시 `context deadline exceeded` 에러
- `kubeadm token create --print-join-command`가 직접 IP(`10.11.132.209:6443`)로 join 커맨드 생성
- cp-2b에서 cp-2a:6443으로 직접 연결 불가 (SG에 CP→CP 6443 규칙 없음)

### 원인
- Track A `kubeadm init` 시 `controlPlaneEndpoint`를 NLB DNS 대신 cp-2a 직접 IP로 설정
- `cluster-info` ConfigMap(kube-public)과 `kubeadm-config` ConfigMap(kube-system) 모두 직접 IP 보유
- join 프로세스가 NLB DNS로 초기 discovery → cluster-info에서 직접 IP 획득 → 직접 IP로 연결 시도 → SG 차단

### 해결
1. `kubeadm-config` ConfigMap의 `controlPlaneEndpoint`를 NLB DNS로 변경
2. `cluster-info` ConfigMap의 server URL을 NLB DNS로 변경
3. cp-2a의 `admin.conf`는 직접 IP 유지 (로컬 접근용)
4. join 커맨드를 NLB DNS 기반으로 재생성

```bash
# kubeadm-config 수정
kubectl get cm kubeadm-config -n kube-system -o json \
  | sed 's|controlPlaneEndpoint: 10.11.132.209:6443|controlPlaneEndpoint: <NLB_DNS>:6443|' \
  | kubectl apply -f -

# cluster-info 수정
kubectl get cm cluster-info -n kube-public -o json \
  | sed 's|https://10.11.132.209:6443|https://<NLB_DNS>:6443|g' \
  | kubectl apply -f -
```

### 예방
- `kubeadm init` 시 `--control-plane-endpoint` 에 반드시 NLB DNS 지정
- 단일 CP로 시작해도 HA 확장 가능성이 있으면 처음부터 NLB endpoint 사용

---

## 문제 2: AMI 드리프트에 의한 기존 인스턴스 재생성 시도

### 증상
- `terraform plan` 시 기존 Track A 인스턴스 3대(cp-2a, worker-2b, worker-2c)가 `forces replacement` 표시
- `data.aws_ami.ubuntu_2404`의 `most_recent = true`가 최신 AMI(`ami-0bcc12a9a835527ef`)를 반환
- 기존 인스턴스의 AMI(`ami-084a56dceed3eb9bb`)와 불일치

### 해결
- Track A 인스턴스의 `ami_id`를 배포 시점 AMI로 하드코딩
- Track B 인스턴스는 `data.aws_ami.ubuntu_2404.id` 유지 (신규 생성이므로 최신 AMI 사용)

### 예방
- 운영 중인 인스턴스는 AMI를 고정하거나 `lifecycle { ignore_changes = [ami] }` 사용
- `most_recent = true` data source는 신규 생성 전용으로 분리

---

## 문제 3: Qdrant 리소스 삭제 혼입

### 증상
- 전체 `terraform plan` 시 Qdrant 관련 리소스 5개가 destroy 대상으로 표시
- Track B와 무관한 변경이 섞임

### 해결
- `-target` 옵션으로 Track B 리소스만 선별 apply

---

## 문제 4: etcd quorum 불안정 + CP 노드 NotReady

### 증상
- cp-2b/2c join 후 etcd CrashLoopBackOff
- etcd member list에는 3대 모두 `started, IS LEARNER = false`로 정상 등록
- cp-2b/2c의 kubelet이 로컬 API server(자기 IP:6443)에 연결 실패
- calico-node init 컨테이너(install-cni) CrashLoopBackOff → CNI 미설치 → NotReady
- quorum(2/3) 미달 시 etcd read-only → API server 기능 저하
  - `kubernetes-admin cannot list resource "nodes"` RBAC 에러 발생

### 관찰
- cp-2a의 kube-controller-manager/kube-scheduler가 이미 138/137회 재시작 (Track B 이전부터 불안정)
- kubelet 재시작으로 etcd 컨테이너가 일시적으로 Running 전환 → 다시 Crash
- worker-2a-1/2a-2는 정상 Ready (worker join은 etcd 포함하지 않으므로 문제 없음)

### 현재 상태 (2026-03-21 15:15 KST)
- cp-2a: Ready, etcd Running, kube-controller-manager/kube-scheduler CrashLoopBackOff
- cp-2b: NotReady, etcd Running(재시작 중), calico-node Init:Error
- cp-2c: NotReady, etcd Running(재시작 중), calico-node Init:Error
- worker 4대: 모두 Ready

### 1차 시도 결론
- 위 문제들이 해결되지 않아 **Track B 인스턴스를 전부 파기하고 처음부터 재시도**

---

## 2차 시도 (2026-03-21) — 해결

### 경과
- Track A 클러스터를 다시 깨끗한 상태에서 시작
- cp-2b join 성공 (초기 재시작 6~7회 후 자체 안정화)
- cp-2c join 성공 (재시작 0회, 깨끗하게 올라옴)
- etcd 3노드 quorum 정상 확보
- worker-2a-1, worker-2a-2 join 성공 (Ready)
- CSR 8개 승인 완료
- NLB 타겟 그룹 attachment 완료

### 문제 5: 새 워커 노드에서 DNS 타임아웃 (pod 네트워크 통신 실패)

#### 증상
- worker-2a-1/2a-2에 스케줄된 spring-boot 파드가 CrashLoopBackOff
- Linkerd proxy: identity 서비스 DNS 해석 실패 (`request timed out`)
- Spring Boot: RDS 호스트 DNS 해석 실패 (`UnknownHostException`)
- busybox 테스트 파드에서 `nslookup kubernetes.default.svc.cluster.local` → `connection timed out`

#### 원인 분석

**Calico IPPool 설정: `vxlanMode: CrossSubnet`**

| 통신 경로 | 캡슐화 | 동작 여부 |
|-----------|--------|----------|
| 다른 서브넷 간 (worker-2b ↔ cp-2a) | VXLAN | 정상 |
| 같은 서브넷 내 (worker-2a-1 ↔ cp-2a) | 직접 라우팅 | **실패** |

기존 Track A에서는 cp-2a(subnet-2a), worker-2b(subnet-2b), worker-2c(subnet-2c)로 모든 노드가 서로 다른 서브넷이라 VXLAN만 사용해서 문제가 없었음.

Track B에서 worker-2a-1, worker-2a-2를 subnet-2a에 추가하면서 cp-2a와 같은 서브넷이 됨 → Calico가 직접 라우팅 사용 → 2가지 원인으로 실패:

1. **AWS Security Group**: 직접 라우팅 패킷의 src/dst가 Pod IP(10.244.x.x). SG에 Pod CIDR 허용 규칙이 없어서 드롭
2. **AWS Source/Destination Check**: 직접 라우팅 패킷의 src/dst가 ENI의 IP와 불일치. 기본 활성화 상태에서 패킷 드롭

참고: VXLAN에서는 외부 패킷이 노드 IP(10.11.x.x, UDP 4789)로 감싸져서 SG/source-dest check 모두 통과함.

#### 잘못된 시도: `vxlanMode: Always`로 변경
- `kubectl patch ippool`으로 변경했으나 tigera-operator가 `Installation` CR 기준으로 즉시 `CrossSubnet`으로 되돌림
- operator가 관리하는 IPPool은 수동 patch가 유지되지 않음
- operator의 설정을 바꾸려면: `kubectl edit installation default` → `spec.calicoNetwork.ipPools[].encapsulation` 변경

#### 해결
1. **EC2 Source/Destination Check 비활성화** (전 노드 7대)
   ```bash
   aws ec2 modify-instance-attribute --instance-id <ID> --no-source-dest-check
   ```
2. **Security Group에 Pod CIDR inbound 허용** (CP SG + Worker SG)
   ```bash
   aws ec2 authorize-security-group-ingress --group-id <SG_ID> --protocol -1 --cidr 10.244.0.0/16
   ```
3. Terraform에 반영:
   - EC2 모듈에 `source_dest_check = false` 변수 추가
   - k8s 노드 7대 모듈에 `source_dest_check = false` 설정
   - SG 규칙 2개 추가 (`k8s_control_plane_ingress_pod_cidr`, `k8s_worker_ingress_pod_cidr`)

#### 검증
- worker-2a-1에서 busybox DNS 테스트 → `nslookup kubernetes.default.svc.cluster.local` 성공
- spring-boot 파드 재생성 → 정상 Running (2/2)

#### 예방
- Calico CrossSubnet 모드 사용 시 **같은 서브넷에 2대 이상 배치하면** 반드시:
  - EC2 source/dest check 비활성화
  - SG에 Pod CIDR(10.244.0.0/16) all traffic inbound 허용
- 또는 `Installation` CR에서 encapsulation을 `VXLAN`(Always)로 변경하면 SG/source-dest check 없이 동작
