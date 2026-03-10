# 5단계: Kubeadm 오케스트레이션

## 1. 오케스트레이션을 도입해야 하는 이유

### 1.1 서비스 개요

Tasteam은 월간 활성 사용자(MAU) 약 500만 규모의 지도 기반 맛집 리뷰 서비스입니다.
주요 기능으로는 음식점 검색, 리뷰 작성, 개인화 추천, AI 기반 리뷰 요약/음식점 평가, 그리고 WebSocket 기반 실시간 채팅이 있습니다.

### 1.2 서비스 특성: 핵심 시간대의 스파이크 트래픽

우리 서비스는 점심(12:00~13:30), 저녁(18:00~20:00)에 트래픽이 자연스럽게 몰리는 스파이크 구조를 가지고 있습니다.
특히 음식점 신규 개장, 맛집 이슈, 그리고 최근 추가된 채팅 서비스로 인해 식사 전 채팅량이 증가하면서 동시 접속과 리뷰 작성 요청이 함께 올라가는 패턴이 뚜렷해지고 있습니다.

이 시간대의 성능 저하는 단순한 응답 지연으로 끝나지 않습니다.
리뷰 작성 포기, 데이터 누락으로 이어지면 네이버 지도·카카오맵 같은 대형 지도 기반 리뷰 서비스에 사용자를 빼앗길 수 있습니다.

따라서 오케스트레이션은 단순히 인프라를 고도화하려는 목적이 아니라, **핵심 시간대의 쓰기 성공률과 사용자 경험을 안정적으로 지키기 위한 고가용성 운영 기반**으로서 필요합니다.

### 1.3 서비스 특성: 실시간 반영과 개인화 업데이트

우리 서비스에는 개인화 추천 기능이 포함되어 있고, 리뷰가 일정량 이상 모이면 AI 리뷰 요약과 음식점 평가가 자동으로 갱신됩니다.
사용자 입장에서는 이러한 변화가 빠르게 반영되어야 서비스를 신뢰할 수 있다고 느끼게 됩니다.

또한 WebSocket 기반 실시간 채팅이 있기 때문에, 피크 시간대에는 API 요청 처리량뿐만 아니라 WebSocket 연결 수와 이벤트 전파량도 함께 증가합니다.
이 경우 연결 유지, 배포 중 연결 안정성까지 함께 관리해야 하므로, 단일 인스턴스 기반 운영으로는 한계가 분명해집니다.

### 1.4 현재 Docker 기반 구조의 한계

현재 Docker + EC2 기반 구성으로도 운영은 가능하지만, 운영을 이어가다 보면 아래와 같은 한계들이 드러납니다.

#### 1.4.1 확장 속도와 확장 단위

| 항목 | 현재 (EC2 Auto Scaling) | 소요 시간 |
|------|-------------------------|-----------|
| 신규 인스턴스 투입 | EC2 시작 + AMI 부팅 | 약 1~1분 30초 |
| 애플리케이션 배포 | CodeDeploy | 약 1분 30초 |
| **총 대응 시간** | | **약 2분 30초~3분** |
| Warm Pool 적용 시 | 대기 인스턴스 활용 | 약 30~90초 |

피크 시간대의 트래픽 급증은 수십 초 단위로 발생할 수 있는데, 2~3분의 대응 시간은 사용자가 체감하기에 충분히 긴 지연입니다.
Warm Pool을 적용하더라도 인스턴스 단위 확장이기 때문에, 채팅 서버 하나만 늘리고 싶어도 EC2 인스턴스 1대를 통째로 띄워야 합니다.

#### 1.4.2 스케일링 시그널의 한계

현재 ASG는 CPU 사용률(`ASGAverageCPUUtilization`)만을 기준으로 확장을 판단하고 있습니다.
하지만 실제 서비스 장애는 CPU가 아닌 다른 지점에서 먼저 나타나는 경우가 많습니다.

- DB 커넥션 풀 고갈로 요청이 대기 상태에 빠지는 경우
- WebSocket 연결 수가 급증하는 경우
- 응답 지연(latency)이 임계치를 넘는 경우

이런 상황에서 CPU는 정상 범위일 수 있어, ASG가 확장을 트리거하지 못합니다.

ASG에서도 CloudWatch Custom Metrics를 직접 push하고 Target Tracking Policy를 구성하면 커스텀 메트릭 기반 스케일링이 가능하긴 합니다.
다만 메트릭을 수집·전송하는 별도 agent나 script를 직접 구현해야 하고, CloudWatch 메트릭 비용도 발생합니다.
K8s HPA는 이미 Prometheus에서 수집 중인 메트릭을 Prometheus Adapter로 바로 연결할 수 있어서, 추가 구현 없이 커스텀 메트릭 기반 스케일링이 가능합니다.

#### 1.4.3 WebSocket 연결과 배포 충돌

현재 CodeDeploy 롤링 배포 시, 배포 대상 인스턴스가 로드밸런서에서 빠지면서 해당 인스턴스에 연결된 **WebSocket 세션이 강제로 끊어집니다.**
채팅 중인 사용자 입장에서는 갑자기 연결이 끊기는 경험을 하게 되며, 피크 시간대에 배포를 하기 부담스러운 구조입니다.

K8s에서는 `terminationGracePeriodSeconds`로 기존 연결을 우아하게 종료할 시간을 확보하고, `PodDisruptionBudget`으로 동시에 내려가는 Pod 수를 제한하여 배포 중에도 WebSocket 연결 안정성을 유지할 수 있습니다.

#### 1.4.4 운영 복잡도: Caddy 기반 라우팅의 구조적 한계

현재는 ALB를 사용하지 않고 Caddy가 외부 진입점(443) 역할을 하면서 백엔드로 트래픽을 라우팅하고 있습니다.
이 구조에서 ASG 인스턴스가 추가/제거될 때 Caddy의 upstream 목록을 동적으로 업데이트해야 하기 때문에, 아래와 같은 체인이 필요합니다:

```
ASG 인스턴스 변경 → ASG Lifecycle Hook → Lambda 실행 → Cloud Map 업데이트 → Caddy upstream 반영
```

이 체인은 장애 발생 시 어느 단계에서 문제가 생겼는지 추적 포인트가 많고, Lambda 실행 실패나 Cloud Map 동기화 지연 같은 부수적인 장애 가능성도 존재합니다.

v3에서는 ALB + K8s Ingress로 전환하면서 Caddy를 제거합니다.
정적 파일은 S3 + CloudFront(CDN)로 분리하고, API 트래픽은 ALB가 Ingress 규칙에 따라 직접 Pod로 라우팅합니다.
서비스 디스커버리는 K8s Service + DNS로 내장 처리되므로, Cloud Map → Lambda SD 체인이 전부 불필요해집니다.

### 1.5 v3 전환 시 함께 개선하는 항목

아래 항목들은 오케스트레이션이 아니더라도 개선 가능하지만, v3 전환과 함께 반영합니다.

- **다중 AZ 분산**: 현재 ASG, Redis, Caddy, NAT가 단일 AZ(2a)에 집중되어 있음. v3에서는 노드를 2a, 2b, 2c 3개 AZ에 분산 배치하여 가용 영역 장애 내성 확보
- **정적 파일 CDN 분리**: Caddy에서 함께 서빙하던 정적 파일을 S3 + CloudFront로 분리

### 1.6 오케스트레이션 도입 시 기대 효과

| 기대 효과 | 현재 (Docker + EC2) | K8s 도입 후 |
|-----------|---------------------|-------------|
| 확장 속도 | 인스턴스 투입까지 2~3분 (Warm Pool 시 30~90초) | Pod 단위 스케일링으로 수십 초 이내 |
| 확장 단위 | EC2 인스턴스 통째로 | Pod 단위로 필요한 컨테이너만 추가 |
| 스케일링 시그널 | CPU만 (커스텀 메트릭은 별도 구현 필요) | Prometheus 메트릭을 HPA에 바로 연결 |
| WebSocket 배포 | 롤링 배포 시 기존 연결 강제 종료 | graceful shutdown + PodDisruptionBudget으로 연결 유지 |
| 배포 안정성 | 인스턴스 단위로 빠지므로 피크 시 가용 용량 감소 | Pod 단위 교체, 새 Pod Ready 후 기존 제거 |
| 서비스 라우팅 | Caddy + Cloud Map + Lambda SD 체인 | ALB + K8s Service + DNS 내장 |

현재 구조에서도 독립 확장과 무중단 배포는 가능합니다.
다만 확장 단위가 인스턴스 전체이고, 스케일링 시그널이 제한적이며, 배포 시 WebSocket 연결이 끊어지고, 서비스 디스커버리 체인의 복잡도가 높다는 점이 운영을 어렵게 만듭니다.
오케스트레이션 도입의 핵심은 이러한 작업의 **단위를 더 작게, 속도를 더 빠르게, 관리를 더 일관되게** 만드는 것입니다.

---

## 2. 왜 kubeadm인가

### 2.1 오케스트레이션 도구 비교

| 항목 | EKS (관리형) | kubeadm (자체 구성) |
|------|-------------|---------------------|
| 컨트롤플레인 관리 | AWS가 관리 | 직접 관리 |
| 비용 | 클러스터당 $0.10/hr (~$73/월) + EC2 비용 | EC2 비용만 발생 |
| 커스터마이징 | 제한적 (AWS 정책 내) | 자유로움 (CNI, 스케줄러, 정책 등) |
| 운영 부담 | 낮음 | 높음 (업그레이드, 인증서 갱신 등 직접 수행) |
| 학습 가치 | Kubernetes 내부 구조를 알기 어려움 | 컨트롤플레인 구성 요소를 직접 이해할 수 있음 |

### 2.2 kubeadm 선택 이유

1. **비용**: EKS 클러스터 비용($73/월)이 추가로 발생하지 않고, 동일한 EC2 위에서 컨트롤플레인을 직접 운영하여 비용을 절감할 수 있습니다.
2. **학습**: Kubernetes의 컨트롤플레인(etcd, kube-apiserver, scheduler, controller-manager)을 직접 구성하고 운영하면서 내부 동작 원리를 깊이 이해할 수 있습니다.
3. **커스터마이징**: CNI, 네트워크 정책, 스케줄링 전략 등을 팀의 요구에 맞게 자유롭게 설정할 수 있습니다.

### 2.3 한계와 전제 조건

- 컨트롤플레인 장애 시 직접 복구해야 합니다. (etcd 백업/복원 계획 필요)
- Kubernetes 버전 업그레이드를 직접 수행해야 합니다.
- 인증서 갱신(기본 1년)을 관리해야 합니다.
- 프로덕션 규모가 커지면 EKS로의 전환도 선택지로 열어두고 있습니다.

## 3. 클러스터 아키텍처 설계

### 3.1 설계 목표

MAU 500만 기준으로, 피크 시간대에 워커 노드 1대가 장애를 겪더라도 서비스가 정상 운영되는 **N+1 가용성**을 확보합니다.

### 3.2 컨트롤플레인: 마스터 3대 (HA)

MAU 500만 규모의 서비스에서 컨트롤플레인이 중단되면 새로운 Pod 생성, 스케일링, 배포가 모두 불가능해집니다.
피크 시간대에 HPA가 동작하지 못하는 상황은 곧 서비스 장애로 이어질 수 있으므로, 컨트롤플레인을 HA로 구성합니다.

| 항목 | 설정 |
|------|------|
| 마스터 노드 수 | 3대 (etcd 쿼럼: 3대 중 2대 생존 시 정상) |
| 인스턴스 타입 | t3.medium (2vCPU, 4GB) |
| AZ 배치 | 2a × 1대, 2b × 1대, 2c × 1대 |
| 역할 | etcd, kube-apiserver, scheduler, controller-manager |

> 마스터 노드 앞에 내부 로드밸런서(NLB)를 두어 API Server 엔드포인트를 단일화합니다.

### 3.3 워커 노드 산정

#### 3.3.1 서비스별 Pod 예상

모니터링(Prometheus, Grafana, Loki)은 stateful 워크로드로 별도 분리 예정이므로 이 산정에서 제외합니다.
WebSocket 채팅은 현재 Spring Boot 내에 포함되어 있습니다.

| 서비스 | 평시 Pod 수 | 피크 시 Pod 수 (HPA) | CPU 요청 | 메모리 요청 |
|--------|------------|---------------------|----------|------------|
| Spring Boot (API + WebSocket) | 2 | 4 | 500m | 1GB |
| FastAPI (AI) | 1 | 2 | 500m | 512MB |
| ArgoCD | 1 | 1 | 200m | 256MB |
| **합계** | **4 Pods** | **7 Pods** | **3,200m** | **5.25GB** |

#### 3.3.2 노드당 allocatable 리소스

t3.medium (2vCPU, 4GB) 기준으로, 시스템 예약과 DaemonSet을 제외한 보수적 추정치입니다.
실제 값은 kubelet의 `--system-reserved`, `--kube-reserved` 설정과 DaemonSet manifest의 resource request에 따라 달라지며, 클러스터 구성 후 `kubectl describe node`로 확인합니다.

| 항목 | CPU | 메모리 |
|------|-----|--------|
| 노드 총 리소스 | 2,000m | 4GB |
| 시스템 예약 (OS, kubelet) | -400m | -512MB |
| DaemonSet (calico-node, kube-proxy) | -350m | -328MB |
| **노드당 allocatable (추정)** | **~1,250m** | **~3.2GB** |

#### 3.3.3 워커 노드 수 결정

```
피크 시 필요: CPU 3,200m, 메모리 5.25GB

워커 3대 allocatable: CPU 3,750m, 메모리 9.6GB → 피크 처리 가능 (N = 3)
워커 2대 (1대 장애): CPU 2,500m → 피크 3,200m 부족
워커 4대 (1대 장애): CPU 3,750m → 피크 3,200m 수용 가능 (N+1 = 4)
```

피크 처리에 최소 3대가 필요하고, 1대 장애를 견디려면 4대가 필요합니다.
3개 AZ에 분산 배치하되, 트래픽이 가장 많은 2a에 2대를 두어 AZ 장애 시에도 최소 3대가 생존하도록 합니다.

### 3.4 최종 클러스터 구성

| 구분 | 대수 | 인스턴스 타입 | AZ 배치 |
|------|------|-------------|---------|
| 마스터 (컨트롤플레인) | 3 | t3.medium (2vCPU, 4GB) | 2a × 1, 2b × 1, 2c × 1 |
| 워커 (애플리케이션) | 4 | t3.medium (2vCPU, 4GB) | 2a × 2, 2b × 1, 2c × 1 |
| **합계** | **7대** | | |

## 4. CNI 네트워크 구성

### 4.1 CNI란

Kubernetes는 자체적으로 Pod 간 네트워크 구현을 포함하지 않고, CNI(Container Network Interface) 플러그인에 위임합니다.
CNI는 Pod에 IP를 할당하고, Pod 간 통신 경로를 설정하며, NetworkPolicy를 적용하는 역할을 합니다.

### 4.2 후보 선별

| CNI | NetworkPolicy | 네트워크 방식 | 프로젝트 상태 | 판정 |
|-----|---------------|--------------|--------------|------|
| Flannel | 미지원 | VXLAN 오버레이 | CoreOS(Red Hat) | **제외** |
| WeaveNet | 기본 지원 | 자체 프로토콜 메시 오버레이 | Weaveworks **2024년 폐업** | **제외** |
| Calico | L3/L4 지원 | BGP 직접 라우팅 | Tigera + CNCF | 최종 후보 |
| Cilium | L3/L4 + L7 지원 | eBPF 네이티브 | Isovalent(Cisco) + CNCF | 최종 후보 |

**Flannel 제외**: Kubernetes의 기본 네트워크는 모든 Pod 간 통신이 열려있는 flat network입니다. Security Group은 EC2(노드) 레벨이라 Pod 단위 트래픽 제어가 불가능하므로, Pod 간 최소 권한 원칙을 적용하려면 NetworkPolicy가 필수적입니다. Flannel은 이를 지원하지 않습니다.

**WeaveNet 제외**: Weaveworks가 2024년에 폐업했습니다. CNI는 한번 선택하면 교체 시 클러스터 재구성이 필요하므로, 유지보수가 불투명한 프로젝트는 프로덕션에서 리스크가 큽니다.

### 4.3 최종 비교: Calico vs Cilium

| 항목 | Calico | Cilium |
|------|--------|--------|
| 데이터플레인 | iptables (기본), eBPF (옵션) | eBPF 네이티브 |
| NetworkPolicy | L3/L4 | L3/L4 + **L7 (HTTP 메서드/경로 제어)** |
| Service Mesh | 미지원 (Istio 별도 설치 → Sidecar 발생) | **자체 내장 (Sidecar 불필요)** |
| Observability | 기본적 | **Hubble 내장 (트래픽 시각화/추적)** |
| 라우팅 | BGP 직접 라우팅 (L3, 오버레이 없음) | VXLAN/Geneve (오버레이) |
| 암호화 | WireGuard (선택적) | WireGuard / IPsec (선택적) |
| 커널 요구사항 | 제한 거의 없음 | **5.10+ 필수** |
| 트러블슈팅 | iptables -L, route -n 등 기존 도구 | 전용 도구 필요 (bpftool, cilium monitor) |

#### Cilium의 강점

- **L7 NetworkPolicy**: 인프라 레벨에서 HTTP 메서드/경로까지 접근 제어 가능
- **Service Mesh 내장**: 별도 Istio 없이 mTLS, 재시도, 로드밸런싱을 eBPF로 처리. Sidecar가 없어 리소스 오버헤드 없음
- **Hubble**: 네트워크 트래픽 흐름을 시각화하고 추적하는 Observability 도구 내장

#### Calico의 강점

- **운영 안정성**: iptables 기반이라 기존 리눅스 네트워크 지식으로 디버깅 가능
- **BGP 직접 라우팅**: 온프레미스 L2 환경에서 오버레이 없이 네이티브에 가까운 성능
- **검증된 조합**: kubeadm + Calico는 가장 보편적인 조합으로 트러블슈팅 자료가 풍부
- **eBPF 전환 가능**: 필요 시 iptables → eBPF 데이터플레인 전환으로 kube-proxy 대체 가능 (설정 변경만으로 전환)

### 4.4 결정: Calico (iptables) + Linkerd

CNI는 **Calico (iptables 데이터플레인)**, Service Mesh는 **Linkerd**를 사용합니다.

#### 4.4.1 eBPF를 선택하지 않은 이유

Cilium의 eBPF 네이티브 아키텍처는 기술적으로 우수하지만, 현재 팀 상황에서는 iptables가 적합합니다.

| 판단 기준 | 현재 상황 |
|-----------|-----------|
| Service 규모 | ~10–20개 수준. iptables 규칙 수가 성능에 영향을 미치는 임계점(수백~수천 규칙)에 한참 못 미침 |
| kube-proxy 부하 | Service 수 적어 iptables 순차 탐색(O(N))이 문제되지 않음. eBPF 해시맵(O(1))의 이점이 체감되지 않는 규모 |
| 팀 역량 | eBPF 운영 경험 없음. 장애 시 `bpftool`, `cilium monitor` 등 전용 도구 학습이 선행되어야 함 |
| 트러블슈팅 | iptables는 `iptables -L`, `route -n`, `tcpdump`로 디버깅 가능. 검색 시 해결 사례 풍부 |
| 전환 경로 | Calico는 설정 변경만으로 iptables → eBPF 데이터플레인 전환 가능. 규모가 커지면 그때 전환해도 늦지 않음 |

eBPF는 Service가 수백 개 이상으로 늘어나 iptables 규칙 탐색이 레이턴시에 영향을 주기 시작할 때, 또는 L7 정책이나 Sidecar 없는 Service Mesh가 필수적이 될 때 검토합니다.

#### 4.4.2 Service Mesh 도입 배경

인프라 팀은 백엔드로부터 jar 파일을 받아 배포하는 구조입니다. 애플리케이션 코드를 수정할 수 없습니다.

서비스 간 통신에서 필요한 아래 기능들을 애플리케이션 코드 변경 없이 인프라 레벨에서 제공하려면 Service Mesh가 필요합니다.

| 기능 | 필요 이유 |
|------|-----------|
| **mTLS** | Pod 간 통신 암호화. 인프라에서 투명하게 적용해야 하며 애플리케이션이 TLS 설정을 직접 관리하지 않아도 됨 |
| **재시도/타임아웃** | 일시적 네트워크 오류나 Pod 재시작 시 자동 재시도. 백엔드 코드에 retry 로직을 심지 않아도 인프라에서 처리 |
| **서킷브레이커** | 장애 서비스로의 요청을 차단하여 연쇄 장애 방지 |
| **Observability** | 서비스 간 성공률, 레이턴시, RPS를 인프라 레벨에서 수집하여 장애 원인 파악 |

#### 4.4.3 Linkerd 선택 이유

Service Mesh 중 Istio와 Linkerd를 비교했습니다.

| 항목 | Istio | Linkerd |
|------|-------|---------|
| 프록시 | Envoy (C++) | linkerd2-proxy (Rust) |
| Sidecar 리소스 | Pod당 ~50–100MB | Pod당 ~10–20MB |
| 설치 복잡도 | 높음 (CRD 다수, 설정 옵션 방대) | `linkerd install \| kubectl apply` 수준 |
| L7 라우팅 | 고급 (헤더 기반, 가중치, fault injection) | 기본 (retry, timeout, traffic split) |
| 프록시 확장성 | WASM 필터로 커스텀 로직 삽입 가능 | 불가 (Rust 프록시, 확장 불가) |
| 비HTTP 프로토콜 | 네이티브 지원 (gRPC, TCP, MongoDB 등) | TCP는 opaque 모드 (L7 기능 미적용) |
| Observability | Kiali 등 별도 구성 필요 | **대시보드 내장** (성공률, 레이턴시, RPS) |

**Istio 대비 Linkerd가 약한 점**

- L7 라우팅/정책 표현 범위가 좁음 (헤더 기반 라우팅, fault injection 등 미지원)
- 프록시 확장성 없음 (Envoy WASM 같은 커스텀 필터 불가)
- 비HTTP 프로토콜은 opaque TCP로만 처리 (L7 기능 미적용)

**팀 기준에서 Linkerd가 충분한 점**

- mTLS 자동 적용 (설치만 하면 Pod 간 통신 암호화)
- 재시도/타임아웃 설정 (ServiceProfile CRD로 경로별 정의)
- Observability: 서비스별 성공률, 레이턴시, RPS를 대시보드에서 바로 확인
- 설치/운영이 단순하여 학습 비용이 낮음
- 카나리 배포, 트래픽 분할 기본 지원

**결론**: 우리 팀의 요구는 **보안(mTLS) + 기본 안정성(retry/timeout) + Observability**입니다.
복잡한 L7 실험(헤더 기반 라우팅, WASM 필터)은 현재 필요하지 않으므로, Linkerd의 기능 범위로 충분합니다.
Istio의 추가 기능은 운영 복잡도 증가 대비 현재 얻을 수 있는 이점이 적습니다.

#### 4.4.4 Linkerd 운영 범위

| 구분 | 적용 | 비고 |
|------|------|------|
| mTLS | ✅ | 전 서비스 자동 적용 |
| 재시도/타임아웃 | ✅ | 핵심 서비스(API → DB, API → AI) 경로에 적용 |
| 기본 메트릭 관측 | ✅ | 성공률, 레이턴시, RPS — Linkerd 대시보드 + Prometheus 연동 |
| 카나리/트래픽 분할 | △ | 필요 시 단계적 도입 |
| 고급 L7 라우팅 | ❌ | 헤더 기반 라우팅, fault injection 등은 범위 밖 |
| 커스텀 프록시 필터 | ❌ | WASM 등 프록시 확장은 범위 밖 |

> **라이선스 참고**: Linkerd의 stable 릴리스는 2024년부터 BUSL로 변경되었으나, edge 릴리스는 Apache 2.0을 유지하고 있습니다. Buoyant(개발사)는 계속 운영 중이며, WeaveNet(폐업)과는 상황이 다릅니다. edge 릴리스를 사용하면 라이선스 제약 없이 운영 가능합니다.

### 4.5 Ingress 및 라우팅 정책

#### 4.5.1 외부 트래픽 진입 구조

현재 Caddy가 담당하는 외부 진입점(443)을 **ALB + Ingress Controller**로 전환합니다.

```
[클라이언트]
    │
    ▼
[Cloudflare] ── DNS + CDN (정적 파일은 S3 + CloudFront)
    │
    ▼
[ALB] ── TLS 종단, 헬스체크
    │
    ▼
[Ingress Controller (NGINX)] ── 경로 기반 라우팅
    │
    ├── /api/*        → Spring Boot Service (ClusterIP)
    ├── /ai/*         → FastAPI Service (ClusterIP)
    └── /ws/*         → Spring Boot Service (WebSocket)
```

#### 4.5.2 Ingress Controller 선택: NGINX

| 항목 | NGINX Ingress | AWS ALB Ingress |
|------|---------------|-----------------|
| 라우팅 제어 | 세밀함 (rewrite, rate limit, custom header) | ALB 규칙 기반 (제한적) |
| WebSocket 타임아웃 | **Ingress 경로별로 read/send timeout 분리 설정 가능** | idle timeout만 제공 (방향 구분 없음) |
| kubeadm 호환 | 추가 설정 없이 동작 | EKS 최적화, kubeadm에서 추가 설정 필요 |
| 클라우드 종속 | 없음 | AWS 종속 (ALB Controller 필요) |

**WebSocket 안정성에서 NGINX를 선택한 이유**

Cloudflare → ALB → NGINX Ingress 구조에서 WebSocket 연결이 끊어지는 원인은 대부분 **타임아웃 설정의 부조화**입니다.

NGINX Ingress는 WebSocket 경로에 **방향별 타임아웃**을 제공합니다.

| annotation | 의미 | WebSocket에서의 역할 |
|------------|------|---------------------|
| `proxy-read-timeout` | 업스트림(Pod)에서 데이터를 기다리는 시간 | 서버가 메시지/ping을 안 보낼 때 NGINX가 끊는 기준 |
| `proxy-send-timeout` | 업스트림(Pod)으로 데이터를 보내는 시간 | 클라이언트 메시지를 백엔드로 전달할 때 백엔드가 안 받으면 끊는 기준 |

ALB는 `idle_timeout.timeout_seconds`(양방향 무트래픽 유휴 시간)만 제어할 수 있어, 경로별 세밀한 타임아웃 조정이 불가능합니다.

우리 서비스는 `/api`(짧은 REST)와 `/ws`(장시간 WebSocket)의 타임아웃 요구가 완전히 다릅니다.
NGINX Ingress는 **Ingress 리소스 단위로 annotation을 분리**할 수 있어, `/ws`에만 긴 타임아웃을 적용하고 `/api`는 기본값을 유지하는 구성이 가능합니다.

> **운영 주의**: Cloudflare → ALB → NGINX 체인에서 **가장 짧은 타임아웃이 실제 한계**입니다.
> WebSocket ping/pong heartbeat 주기를 모든 레이어의 타임아웃보다 짧게 설정해야 유휴 종료를 방지할 수 있습니다.

#### 4.5.3 Ingress 규칙 예시

WebSocket(`/ws`)과 일반 API(`/api`, `/ai`)를 **별도 Ingress 리소스로 분리**하여 타임아웃을 독립 관리합니다.

```yaml
# 일반 API Ingress — 기본 타임아웃 사용
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tasteam-api-ingress
  namespace: prod
spec:
  ingressClassName: nginx
  rules:
    - host: tasteam.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: spring-boot-svc
                port:
                  number: 8080
          - path: /ai
            pathType: Prefix
            backend:
              service:
                name: fastapi-svc
                port:
                  number: 8000
---
# WebSocket Ingress — 장시간 연결 유지
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tasteam-ws-ingress
  namespace: prod
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
    - host: tasteam.example.com
      http:
        paths:
          - path: /ws
            pathType: Prefix
            backend:
              service:
                name: spring-boot-svc
                port:
                  number: 8080
```

`/api`, `/ai`는 기본 타임아웃(60초)으로 충분하고, `/ws`만 3600초로 설정하여 채팅 연결이 유지되도록 합니다.

#### 4.5.4 내부 서비스 간 통신

Pod 간 내부 통신은 K8s **ClusterIP Service + DNS**로 처리합니다.

```
Spring Boot Pod → fastapi-svc.prod.svc.cluster.local:8000 → FastAPI Pod
```

- 서비스 디스커버리: CoreDNS가 Service 이름을 자동 해석
- 로드밸런싱: kube-proxy(iptables)가 Service IP → 실제 Pod IP로 분산
- mTLS: Linkerd Sidecar가 투명하게 암호화 처리

외부 Cloud Map, Lambda SD 같은 별도 디스커버리 체인이 불필요합니다.

### 4.6 NetworkPolicy 운영 방침

아래 순서로 NetworkPolicy를 적용합니다.

| 순서 | 정책 | 설명 |
|------|------|------|
| 1 | DNS 허용 | 모든 Pod → CoreDNS(kube-system) 통신 허용 |
| 2 | 기본 Deny | namespace 단위 Ingress/Egress 기본 차단 |
| 3 | 서비스별 허용 | 필요한 Pod 간 통신만 명시적으로 허용 |

> **주의**: DNS 허용 정책을 먼저 적용하지 않으면 서비스 디스커버리가 차단되어 전체 통신 장애가 발생합니다.

#### NetworkPolicy 예시: DB Pod 접근 제한

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-allow-backend-only
  namespace: app
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: backend
      ports:
        - protocol: TCP
          port: 5432
```

### 4.7 암호화 정책

서비스 간 통신 암호화는 **Linkerd mTLS**가 기본으로 처리합니다.
Linkerd가 설치된 namespace의 Pod 간 통신은 자동으로 mTLS가 적용되므로, 별도 인증서 관리 없이 전송 구간 암호화가 확보됩니다.

Calico WireGuard는 Linkerd가 관여하지 않는 구간(예: Linkerd mesh 외부의 시스템 Pod 간 통신)에서 필요할 경우 선택적으로 활성화합니다.
기본적으로는 Linkerd mTLS만으로 충분하며, WireGuard는 비활성화 상태로 시작합니다.

## 5. 서비스 배포 전략

### 5.1 Namespace 구성

| Namespace | 용도 | 포함 리소스 |
|-----------|------|------------|
| `dev` | 개발·기능 테스트 | Spring Boot, FastAPI, Service, Ingress, ConfigMap, Secret |
| `stg` | 통합 테스트·부하 테스트 | Spring Boot, FastAPI, Service, Ingress, ConfigMap, Secret |
| `prod` | 운영 | Spring Boot, FastAPI, Service, Ingress, ConfigMap, Secret |
| `monitoring` | 모니터링 스택 (별도 단계) | Prometheus, Grafana, Loki |
| `argocd` | GitOps 배포 관리 | ArgoCD server, repo-server, controller |

### 5.2 Deployment 구성

#### Spring Boot (API + WebSocket)

<details>
<summary>Deployment YAML</summary>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-boot
  namespace: prod
spec:
  replicas: 2
  progressDeadlineSeconds: 120  # 2분 내 배포 진행 없으면 실패 판정 (5.8 참조)
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    spec:
      containers:
        - name: spring-boot
          image: <ECR_URI>/spring-boot:latest
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 1000m
              memory: 2Gi
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 15
            failureThreshold: 3
          env:
            - name: SPRING_PROFILES_ACTIVE
              valueFrom:
                configMapKeyRef:
                  name: spring-config
                  key: profile
```

</details>

#### FastAPI (AI)

<details>
<summary>Deployment YAML</summary>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi
  namespace: prod
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    spec:
      containers:
        - name: fastapi
          image: <ECR_URI>/fastapi:latest
          ports:
            - containerPort: 8000
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 15
            periodSeconds: 15
            failureThreshold: 3
```

</details>

### 5.3 배포 전략: Rolling Update

`maxSurge: 1, maxUnavailable: 0` 설정으로, 새 Pod가 Ready 상태가 된 후에야 기존 Pod를 제거합니다.
이를 통해 배포 중에도 가용 Pod 수가 줄어들지 않으며, 피크 시간대에도 안전하게 배포할 수 있습니다.

### 5.4 Probe 설계

| Probe | 역할 | 실패 시 동작 |
|-------|------|-------------|
| readinessProbe | 트래픽을 받을 준비가 되었는지 확인 | Service에서 해당 Pod로의 트래픽 제외 |
| livenessProbe | 프로세스가 정상 동작하는지 확인 | Pod 재시작 |

readinessProbe는 배포 직후 애플리케이션이 초기화되는 동안 트래픽이 유입되는 것을 방지합니다.
livenessProbe는 프로세스가 살아있지만 응답 불가(hang)인 상태를 감지하여 자동으로 재시작합니다.

### 5.5 Service 구성

<details>
<summary>Service YAML</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: spring-svc
  namespace: prod
spec:
  type: ClusterIP
  selector:
    app: spring-boot
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-svc
  namespace: prod
spec:
  type: ClusterIP
  selector:
    app: fastapi
  ports:
    - port: 80
      targetPort: 8000
```

</details>

### 5.6 Ingress (ALB)

Caddy를 제거하고 ALB + AWS Load Balancer Controller로 외부 트래픽을 라우팅합니다.
정적 파일은 S3 + CloudFront(CDN)로 분리하고, ALB는 API 트래픽만 처리합니다.

<details>
<summary>Ingress YAML</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: prod
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
    - host: api.tasteam.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: spring-svc
                port:
                  number: 80
          - path: /ai
            pathType: Prefix
            backend:
              service:
                name: fastapi-svc
                port:
                  number: 80
```

</details>

### 5.7 설정 관리

| 리소스 | 용도 | 소스 |
|--------|------|------|
| ConfigMap | 환경 설정 (프로필, 외부 URL 등) | Git 관리 |
| Secret | 민감 정보 (DB 비밀번호, API 키 등) | Sealed Secrets로 암호화하여 Git 관리 (7.5 참조) |

### 5.8 배포 실패 시 자동 보호 및 롤백

#### 5.8.1 자동 보호 메커니즘

5.3의 `maxUnavailable: 0`과 5.4의 readinessProbe가 조합되어, 새 Pod가 Probe를 통과하지 못하면 배포가 자연스럽게 **중단(stall)** 됩니다.
기존 Pod는 제거되지 않으므로 서비스에는 영향이 없습니다.

여기에 `progressDeadlineSeconds: 120` (5.2 Deployment에 설정)을 더하면, 2분 내 배포가 진행되지 않을 경우 Deployment 상태가 자동으로 `Progressing=False`로 전환되고, ArgoCD가 Degraded 상태로 표시하여 운영자에게 알립니다.

```
[정상 배포 흐름]
새 Pod 생성 → readinessProbe 통과 → Service에 등록 → 기존 Pod 제거 → 완료

[실패 배포 흐름]
새 Pod 생성 → readinessProbe 실패 반복 → Service에 등록되지 않음
  → maxUnavailable=0이므로 기존 Pod 제거 안 됨 (서비스 영향 없음)
  → progressDeadlineSeconds 초과 → Deployment 상태 "Progressing=False"
  → ArgoCD가 Degraded 상태로 표시 → 운영자에게 알림
```

#### 5.8.2 실패 감지 후 조치

배포가 `progressDeadlineSeconds`를 초과하여 실패 판정된 경우:

<details>
<summary>실패 감지 및 롤백 명령어</summary>

```bash
# 1. 배포 상태 확인 — "Progressing=False" 조건 확인
$ kubectl rollout status deployment/spring-boot -n prod
# → "error: deployment "spring-boot" exceeded its progress deadline"

# 2. 실패한 새 Pod의 로그 확인
$ kubectl logs -l app=spring-boot -n prod --tail=50

# 3. 이벤트 확인 — readinessProbe 실패 원인 파악
$ kubectl describe pod -l app=spring-boot -n prod | grep -A5 "Events"

# 4. 직전 버전으로 롤백
$ kubectl rollout undo deployment/spring-boot -n prod

# 5. 롤백 완료 확인
$ kubectl rollout status deployment/spring-boot -n prod
```

</details>

> `kubectl rollout undo`는 긴급 대응용입니다. Git과 클러스터 상태가 불일치(OutOfSync)하므로, 이후 cloud-repo에서 `git revert`로 Git 상태를 동기화해야 합니다.

#### 5.8.3 배포 보호 흐름 요약

```
[배포 시작]
  → 새 Pod 생성
  → readinessProbe 실행
      ├─ 성공 → Service에 등록 → 트래픽 수신 → 기존 Pod 제거 → 배포 완료
      └─ 실패 → Service에 미등록 → 트래픽 차단 → 기존 Pod 유지 (서비스 무영향)
                  → progressDeadlineSeconds 초과 → 실패 판정
                  → ArgoCD Degraded / 알림
                  → 운영자 확인 후 rollout undo 또는 git revert

[배포 완료 후]
  → livenessProbe가 지속 감시
      ├─ 정상 → Pod 유지
      └─ 실패 (hang 등) → Pod 자동 재시작 → readinessProbe 재통과 후 트래픽 복귀
```

#### 5.8.4 자동 롤백을 도입하지 않는 이유

- readinessProbe + `maxUnavailable: 0`이 이미 서비스를 보호하므로, 운영자가 판단할 시간이 충분
- 배포 실패 원인이 코드가 아닌 일시적 외부 요인(DB 연결 지연, ConfigMap 누락 등)일 수 있어, 자동 revert는 불필요한 롤백을 유발할 수 있음
- Argo Rollouts(Canary/Blue-Green 기반 메트릭 자동 롤백)는 현재 구성(Deployment + ArgoCD) 대비 오버스펙. 규모가 커져 Canary 배포가 필요해지면 도입 검토

---

## 6. 스케일링 전략
### 6.1 HPA (Horizontal Pod Autoscaler)

피크 시간대 트래픽 급증에 Pod 단위로 자동 대응합니다.

#### Spring Boot HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: spring-boot-hpa
  namespace: prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: spring-boot
  minReplicas: 2
  maxReplicas: 4
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

#### FastAPI HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fastapi-hpa
  namespace: prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fastapi
  minReplicas: 1
  maxReplicas: 2
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

### 6.2 커스텀 메트릭 확장 (추후)

현재는 CPU 기반으로 시작하고, 운영 데이터가 쌓이면 Prometheus Adapter를 통해 커스텀 메트릭 기반 스케일링을 도입합니다.

| 단계 | 메트릭 | 도구 |
|------|--------|------|
| 1단계 (1주차 - 초기) | CPU Utilization | HPA 기본 |
| 2단계 (2주차 - 운영) | 요청 수, 응답 지연, WebSocket 연결 수 | Prometheus Adapter + HPA custom metrics |

### 6.3 클러스터 오토스케일링

HPA가 Pod를 늘려도 노드에 allocatable 리소스가 남아있지 않으면 Pod는 Pending 상태에 머뭅니다.
피크 시간대에 노드 리소스가 소진되는 상황에 자동 대응하기 위해 Cluster Autoscaler를 도입합니다.

#### 6.3.1 도구 선택: Cluster Autoscaler

Karpenter는 ASG 없이 EC2를 직접 프로비저닝하며, Pod request에 맞는 인스턴스 타입을 실시간으로 선택하고 Spot 활용·노드 통합까지 자동화하는 점에서 대규모 환경에 유리합니다.
다만 노드 라이프사이클 관리가 EKS의 IAM 기반 인증(`aws-auth`)을 전제로 설계되어 있어, kubeadm 환경에서는 노드 등록·추적·삭제 과정에서 별도 커스텀 작업이 필요합니다.

Cluster Autoscaler는 ASG의 `DesiredCapacity`만 조절하고, 인스턴스 부팅과 join은 Launch Template의 UserData(`kubeadm join`)에 위임하므로 kubeadm과 자연스럽게 결합됩니다.

#### 6.3.2 운영 전략

| 항목 | 설정 |
|------|------|
| ASG 범위 | min: 4 / max: 6 (워커 노드) |
| 스케일업 트리거 | Pending Pod 발생 시 |
| 스케일다운 조건 | 노드 사용률 50% 미만이 10분 이상 지속 |
| 스케일다운 보호 | PDB 준수, `terminationGracePeriodSeconds` 대기 후 drain |

- **스케일업**: HPA가 Pod를 늘려 Pending이 발생하면, Cluster Autoscaler가 ASG DesiredCapacity를 증가시켜 새 노드를 투입
- **스케일다운**: 피크 이후 Pod가 축소되어 노드 사용률이 낮아지면, 해당 노드의 Pod를 drain한 뒤 노드를 제거. PDB를 준수하므로 WebSocket 연결이 보호됨
- **Join 자동화**: Launch Template UserData에 `kubeadm join` 스크립트를 포함하여 새 노드가 부팅 시 자동으로 클러스터에 합류

---

## 7. 배포 고도화 (Helm, ArgoCD)

### 7.1 Manifest 관리 방식

| 대상 | 관리 방식 | 이유 |
|------|-----------|------|
| 애플리케이션 (Spring, FastAPI) | 순수 YAML | 직접 작성하여 구조를 이해하고, 환경별 차이를 명확하게 관리 |
| 외부 스택 (ALB Controller, ArgoCD, Sealed Secrets) | Helm Chart | 복잡한 외부 도구를 안정적으로 설치·관리 |

### 7.2 환경 격리 방식

단일 클러스터 내에서 namespace로 환경을 분리합니다.

| 환경 | Namespace | 용도 |
|------|-----------|------|
| dev | `dev` | 개발·기능 테스트 |
| stg | `stg` | 통합 테스트·부하 테스트 |
| prod | `prod` | 운영 |

- NetworkPolicy로 namespace 간 트래픽을 차단하여 환경 간 간섭 방지
- ResourceQuota로 dev/stg가 prod의 리소스를 침범하지 않도록 제한
- 클러스터 분리나 AWS 계정 분리는 현재 규모 대비 비용/운영 부담이 과도하여 채택하지 않음

### 7.3 디렉토리 구조

```
v3-k8s/
  manifests/
    app/
      base/                   # 공통 YAML
        deployment.yaml
        service.yaml
        ingress.yaml
        configmap.yaml
        hpa.yaml
      overlays/               # 환경별 오버라이드 (Kustomize)
        dev/
          kustomization.yaml
        stg/
          kustomization.yaml
        prod/
          kustomization.yaml
    helm/
      values/
        alb-controller.yaml
        argocd.yaml
        sealed-secrets.yaml
  argocd/                     # ArgoCD Application 정의
    dev.yaml
    stg.yaml
    prod.yaml
```

- `base/`: 모든 환경에 공통인 리소스 정의
- `overlays/`: 환경별로 replicas, 이미지 태그, 리소스 제한 등을 Kustomize patch로 오버라이드
- `argocd/`: ArgoCD가 각 환경을 바라보는 Application CR 정의

### 7.4 ArgoCD

#### 7.4.1 GitOps 배포 방식

ArgoCD는 Pull 기반 GitOps 도구입니다.
CI 파이프라인이 클러스터에 직접 배포하는 Push 방식과 달리, ArgoCD가 Git 저장소를 주기적으로 감시하여 변경을 감지하고 클러스터에 반영합니다.

```
[Push 방식 (기존)]
개발자 → git push → CI → kubectl apply (CI가 클러스터 접근 권한 필요)

[Pull 방식 (ArgoCD)]
개발자 → git push → CI → 이미지 빌드/푸시 → manifest 이미지 태그 업데이트
                                              ↓
                              ArgoCD가 Git 변경 감지 → 클러스터에 반영
```

Pull 방식의 이점:
- CI 파이프라인에 클러스터 접근 권한(kubeconfig)을 부여하지 않아도 됨
- Git이 단일 진실 공급원(Single Source of Truth)이 되어, 클러스터 상태가 항상 Git과 일치
- 누가, 언제, 무엇을 배포했는지 Git 커밋 히스토리로 추적 가능

#### 7.4.2 멀티 레포 전략

애플리케이션 코드와 K8s manifest를 별도 레포에서 관리합니다.

| 레포 | 역할 | 관리 주체 |
|------|------|-----------|
| frontend-repo | React 소스 코드 + CI | 프론트엔드 개발자 |
| backend-repo | Spring Boot 소스 코드 + CI | 백엔드 개발자 |
| ai-repo | FastAPI 소스 코드 + CI | AI 개발자 |
| cloud-repo | K8s manifest + ArgoCD Application + 인프라 코드 | 클라우드 담당 |

- 개발자는 코드만 푸시하면 되고, K8s manifest를 알 필요 없음
- manifest 변경(포트, 환경변수, 리소스 등)은 클라우드 담당자가 cloud-repo에서 관리
- ArgoCD는 cloud-repo만 감시

**한계:**
- 각 서비스 CI에서 cloud-repo에 cross-repo commit이 필요 (GitHub App 토큰 관리)
- 동시 빌드 시 같은 파일을 수정하면 push 충돌 가능 → 서비스별 이미지 태그 파일 분리로 대응
- 배포 추적 시 이미지 태그(SHA) → 원본 레포 커밋을 역추적해야 함

#### 7.4.3 배포 파이프라인

```
[backend-repo CI]
1. 개발자 코드 푸시 (backend-repo)
2. GitHub Actions → Docker 이미지 빌드 → ECR 푸시 (태그: git SHA)
3. GitHub Actions → cloud-repo의 manifest 이미지 태그를 새 SHA로 업데이트 (cross-repo commit)

[ai-repo CI]
1. 개발자 코드 푸시 (ai-repo)
2. GitHub Actions → Docker 이미지 빌드 → ECR 푸시 (태그: git SHA)
3. GitHub Actions → cloud-repo의 manifest 이미지 태그를 새 SHA로 업데이트 (cross-repo commit)

[frontend-repo CI]
1. 개발자 코드 푸시 (frontend-repo)
2. GitHub Actions → 정적 파일 빌드 → S3 + CloudFront 배포
3. (K8s 배포 불필요 - CDN을 통해 직접 서빙)

[ArgoCD]
4. cloud-repo의 manifest 변경 감지 → 환경별 정책에 따라 클러스터 동기화
```

cross-repo commit은 `github-actions[bot]` 계정으로 수행되며, 커밋 메시지에 원본 레포의 커밋 SHA를 포함하여 추적성을 확보합니다.

#### 7.4.4 환경별 동기화 정책

| 환경 | 동기화 방식 | 이유 |
|------|------------|------|
| dev | **자동 동기화** (Auto Sync) | 매일 수회 배포, 빠른 피드백 필요 |
| stg | **수동 동기화** (Manual Sync) | 부하 테스트 등 진행 중 의도치 않은 배포 방지 |
| prod | **수동 동기화** (Manual Sync) | 클라우드 담당자가 ArgoCD UI에서 명시적으로 Sync 버튼 클릭 |

- dev: Git에 manifest가 반영되면 ArgoCD가 즉시 클러스터에 동기화
- stg/prod: Git에 manifest가 반영되어도 ArgoCD는 "OutOfSync" 상태만 표시. 클라우드 담당 2인 중 1인이 확인 후 수동으로 Sync 실행

#### 7.4.5 ArgoCD Application 예시 (prod)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tasteam-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/100-hours-a-week/3-team-Tasteam-cloud.git
    targetRevision: main
    path: v3-k8s/manifests/app/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
  syncPolicy:
    # prod는 자동 동기화 비활성화 (수동 승인)
    automated: null
```

dev Application에서는 `syncPolicy`에 아래를 추가합니다:

```yaml
  syncPolicy:
    automated:
      prune: true       # Git에서 삭제된 리소스를 클러스터에서도 삭제
      selfHeal: true     # 수동 변경(kubectl edit 등)을 Git 상태로 자동 되돌림
```

### 7.5 Secret 관리

#### 7.5.1 문제

GitOps에서는 모든 리소스를 Git에 저장하는 것이 원칙이지만, Secret(DB 비밀번호, API 키 등)은 평문으로 Git에 커밋할 수 없습니다.

#### 7.5.2 방식: Sealed Secrets

Sealed Secrets(Bitnami)를 사용하여 Secret을 암호화된 형태로 Git에 저장합니다.

```
[암호화 흐름]
1. 클러스터에 Sealed Secrets Controller 설치 (복호화 키 보유)
2. 로컬에서 kubeseal CLI로 Secret을 암호화 → SealedSecret 리소스 생성
3. SealedSecret을 Git에 커밋 (암호화된 상태이므로 안전)
4. ArgoCD가 SealedSecret을 클러스터에 배포
5. Sealed Secrets Controller가 복호화 → 실제 Secret 리소스 생성
```

```bash
# 암호화 예시
kubectl create secret generic db-credentials \
  --from-literal=password=my-secret-pw \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-db-credentials.yaml
```

```yaml
# sealed-db-credentials.yaml (Git에 커밋 가능)
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-credentials
  namespace: prod
spec:
  encryptedData:
    password: AgBy3i4OJSWK+PiTySYZZA9rO...  # 암호화된 값
```

#### 7.5.3 Sealed Secrets 선택 이유

| 방식 | 장점 | 단점 | 판정 |
|------|------|------|------|
| AWS SSM + ExternalSecrets | AWS 네이티브, Secret 중앙 관리 | ExternalSecrets Operator 추가 설치, AWS IAM 연동 필요 | 후보 |
| HashiCorp Vault | 강력한 접근 제어, 동적 시크릿 | 별도 Vault 클러스터 운영 필요, 과도한 복잡도 | 제외 |
| **Sealed Secrets** | **Git 단일 관리, 추가 인프라 불필요, 단순함** | **Secret 갱신 시 재암호화 필요** | **선택** |

- 현재 팀 규모(6인, 클라우드 2인)에서 Vault는 운영 부담이 과도함
- Sealed Secrets는 Git에 모든 것을 저장한다는 GitOps 원칙과 가장 잘 부합
- Secret 갱신이 빈번하지 않으므로 재암호화 비용이 낮음

---

## 8. 장애 대응 및 자동 복구
### 8.1 Pod 레벨

| 장애 유형 | 대응 | 설정 |
|-----------|------|------|
| 컨테이너 crash | 자동 재시작 | `restartPolicy: Always` (Deployment 기본값) |
| 프로세스 hang | liveness probe 실패 → 재시작 | `livenessProbe` (5.4 참조) |
| 배포 중 트래픽 유입 | readiness probe 통과 전 트래픽 제외 | `readinessProbe` (5.4 참조) |

### 8.2 WebSocket 연결 보호

```yaml
# Pod 종료 시 기존 연결을 정리할 시간 확보
terminationGracePeriodSeconds: 60
---
# 동시에 내려갈 수 있는 Pod 수 제한
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: spring-boot-pdb
  namespace: prod
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: spring-boot
```

배포나 노드 유지보수 시에도 최소 1개의 Spring Boot Pod가 항상 유지되어 WebSocket 연결이 전부 끊어지는 상황을 방지합니다.

### 8.3 노드 레벨

| 장애 유형 | K8s 자동 대응 |
|-----------|--------------|
| 워커 노드 1대 장애 | 해당 노드의 Pod를 다른 노드로 자동 재스케줄링 (N+1 설계로 수용 가능) |
| 마스터 노드 1대 장애 | etcd 쿼럼 유지 (3대 중 2대 생존), API Server는 NLB가 정상 노드로 라우팅 |
| 마스터 노드 2대 장애 | etcd 쿼럼 상실 → 컨트롤플레인 중단 (기존 Pod는 계속 동작, 새 배포/스케일링 불가) |

### 8.4 etcd 백업

마스터 노드 전체 장애에 대비하여 etcd를 정기적으로 백업합니다.

```bash
# etcd 스냅샷 백업
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

백업 주기와 저장 위치(S3 등)는 운영 단계에서 결정합니다.

---

## 9. 클러스터 구성도

```
                         ┌──────────────────┐
                         │    Cloudflare     │
                         └────────┬─────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
            ┌───────▼───────┐          ┌────────▼────────┐
            │  CloudFront   │          │   ALB (public)  │
            │  + S3 (정적)  │          │                 │
            └───────────────┘          └────────┬────────┘
                                                │
                              ┌─────────────────┼─────────────────┐
                              │         K8s Cluster (3AZ)         │
                              │                                   │
                              │  ┌─── Master (HA, 3대, 3AZ) ───┐ │
                              │  │ etcd, apiserver, scheduler,  │ │
                              │  │ controller-manager           │ │
                              │  │         ↕ NLB               │ │
                              │  └──────────────────────────────┘ │
                              │                                   │
                              │  ┌─── Worker (4대, 3AZ) ───────┐ │
                              │  │                              │ │
                              │  │  ┌── NGINX Ingress ───────┐ │ │
                              │  │  │  /api, /ai → ClusterIP │ │ │
                              │  │  │  /ws → ClusterIP (WS)  │ │ │
                              │  │  └────────────┬───────────┘ │ │
                              │  │               │              │ │
                              │  │     ┌─────────┴─────────┐   │ │
                              │  │     │  Linkerd mTLS      │   │ │
                              │  │     └─────────┬─────────┘   │ │
                              │  │               │              │ │
                              │  │  ┌────────────┴───────────┐ │ │
                              │  │  │                        │ │ │
                              │  │  │  ┌─────────┐ ┌──────┐ │ │ │
                              │  │  │  │ Spring  │ │Fast  │ │ │ │
                              │  │  │  │ Boot    │ │API   │ │ │ │
                              │  │  │  │ ×2~4    │ │×1~2  │ │ │ │
                              │  │  │  └────┬────┘ └──┬───┘ │ │ │
                              │  │  │       │         │     │ │ │
                              │  │  │  spring-svc  fastapi  │ │ │
                              │  │  │  (ClusterIP) -svc    │ │ │
                              │  │  └────────────────────────┘ │ │
                              │  │                              │ │
                              │  │  ┌───────────┐              │ │
                              │  │  │  ArgoCD   │              │ │
                              │  │  │  ×1       │              │ │
                              │  │  └───────────┘              │ │
                              │  └──────────────────────────────┘ │
                              │                                   │
                              └───────────┬───────────────────────┘
                                          │
                              ┌───────────▼───────────┐
                              │  External Services    │
                              │  - RDS (PostgreSQL)   │
                              │  - EC2 Redis          │
                              └───────────────────────┘
```

### 트래픽 흐름

```
정적 파일:  User → Cloudflare → CloudFront → S3
API 요청:   User → Cloudflare → ALB → NGINX Ingress → spring-svc → Spring Pods
AI 요청:    User → Cloudflare → ALB → NGINX Ingress → fastapi-svc → FastAPI Pods
WebSocket:  User → Cloudflare → ALB → NGINX Ingress (/ws, timeout 3600s) → Spring Pods
내부 통신:  Spring Pods →[Linkerd mTLS]→ fastapi-svc (ClusterIP, DNS)
DB 접근:    Spring Pods → RDS (외부, Private Subnet)
```

## 10. 설정 명세


## 11. 운영 시나리오

### 11.1 피크 시간대 자동 확장

```
12:00 점심 피크 시작
  → Spring Boot CPU 사용률 70% 초과
  → HPA가 감지 → replicas 2 → 3 → 4 (수십 초 이내)
  → 새 Pod에 Linkerd sidecar 자동 주입 → mTLS 즉시 적용
  → readinessProbe 통과 후 NGINX Ingress가 트래픽 분산 시작

13:30 피크 종료
  → CPU 사용률 하락
  → HPA cooldown 후 replicas 4 → 3 → 2 (점진적 축소)
  → 축소 대상 Pod: terminationGracePeriodSeconds(60초) 동안 기존 WebSocket 연결 유지 후 종료
```

### 11.2 워커 노드 장애

```
워커 노드 1대 (2a) 장애 발생
  → 해당 노드의 Pod가 NotReady 상태
  → NGINX Ingress가 NotReady Pod로의 트래픽 즉시 차단
  → K8s controller가 5분 내 다른 노드로 Pod 재스케줄링
  → 남은 3대(2a×1, 2b×1, 2c×1)로 피크 트래픽 수용 가능 (N+1 설계)
  → 재스케줄링된 Pod에 Linkerd sidecar 자동 주입, mTLS 정상 동작
  → 장애 노드 복구 후 Pod가 자동으로 재분배
```

### 11.3 AZ 장애

```
AZ 2b 전체 장애
  → 마스터 1대 + 워커 1대 손실
  → 마스터: 2대 생존 (2a, 2c) → etcd 쿼럼 유지, 컨트롤플레인 정상
  → 워커: 3대 생존 (2a×2, 2c×1) → 피크 트래픽 수용 가능
  → NLB가 정상 API Server로 라우팅, ALB가 정상 워커로 트래픽 분산
  → HPA, 배포, 스케일링 모두 정상 동작

AZ 2a 전체 장애 (워커 2대 손실, 가장 큰 영향)
  → 마스터: 2대 생존 (2b, 2c) → etcd 쿼럼 유지
  → 워커: 2대 생존 (2b×1, 2c×1) → allocatable CPU 2,500m
  → 피크 시 필요 CPU 3,200m → 부족 발생
  → 평시 트래픽은 수용 가능, 피크 시 일부 Pod 스케줄링 불가
  → 장애 복구 또는 다른 AZ에 워커 추가 투입으로 대응
```

### 11.4 롤링 배포

```
새 버전 배포 시작
  → ArgoCD가 Git의 이미지 태그 변경 감지
  → maxSurge=1: 새 Pod 1개 생성 (Linkerd sidecar 자동 주입)
  → 새 Pod의 readinessProbe 통과 확인
  → NGINX Ingress가 새 Pod로 트래픽 분산 시작
  → maxUnavailable=0: 기존 Pod 1개 제거 시작
  → PodDisruptionBudget: Spring Boot Pod 최소 1개 유지 보장
  → 제거 대상 Pod: terminationGracePeriodSeconds(60초) 동안 기존 WebSocket 연결 유지
  → NGINX Ingress의 /ws timeout(3600s) 덕분에 배포 중 유휴 WebSocket 연결도 유지
  → 위 과정을 replica 수만큼 반복
  → 전체 과정에서 가용 Pod 수가 줄어들지 않음
```

### 11.5 마스터 노드 장애

```
마스터 1대 장애 (어느 AZ든 동일)
  → etcd 쿼럼 유지 (2/3 생존)
  → NLB가 정상 API Server로 라우팅
  → kubectl, HPA, 배포 모두 정상 동작
  → 장애 노드 복구 후 etcd 자동 동기화

마스터 2대 장애 (극단적 상황)
  → etcd 쿼럼 상실 → 컨트롤플레인 중단
  → 기존 Pod는 계속 동작 (서비스 유지)
  → Linkerd sidecar도 기존 상태로 동작 (mTLS 유지)
  → NGINX Ingress 라우팅 유지 (기존 규칙 기반)
  → 새 배포, 스케일링, Pod 재스케줄링 불가
  → etcd 스냅샷으로 복구
```

### 11.6 WebSocket 채팅 피크 시나리오

```
18:00 저녁 피크 — 채팅 동시 접속 급증
  → WebSocket 연결 수 증가 → Spring Boot Pod 부하 상승
  → HPA가 CPU 70% 초과 감지 → Pod 확장
  → NGINX Ingress: 새 WebSocket 연결은 새 Pod로 분산
  → 기존 연결은 기존 Pod에서 유지 (sticky)
  → ALB idle_timeout, NGINX proxy-read-timeout 모두 heartbeat 주기보다 길게 설정
  → 채팅방이 조용해도 ping/pong heartbeat로 연결 유지
```
