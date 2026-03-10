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

- **다중 AZ 분산**: 현재 ASG, Redis, Caddy, NAT가 단일 AZ(2a)에 집중되어 있음. v3에서는 워커 노드를 2a, 2c에 분산 배치하여 가용 영역 장애 내성 확보
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
| AZ 배치 | 2a × 2대, 2c × 1대 |
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
4대는 AZ 균등 배치(2a × 2, 2c × 2)에도 맞아떨어집니다.

### 3.4 최종 클러스터 구성

| 구분 | 대수 | 인스턴스 타입 | AZ 배치 |
|------|------|-------------|---------|
| 마스터 (컨트롤플레인) | 3 | t3.medium (2vCPU, 4GB) | 2a × 2, 2c × 1 |
| 워커 (애플리케이션) | 4 | t3.medium (2vCPU, 4GB) | 2a × 2, 2c × 2 |
| **합계** | **7대** | | |


## 4. 서비스 배포 전략

### 4.1 Namespace 구성

| Namespace | 용도 | 포함 리소스 |
|-----------|------|------------|
| `app` | 애플리케이션 서비스 | Spring Boot, FastAPI, Service, Ingress, ConfigMap, Secret |
| `monitoring` | 모니터링 스택 (별도 단계) | Prometheus, Grafana, Loki |
| `argocd` | GitOps 배포 관리 | ArgoCD server, repo-server, controller |

### 4.2 Deployment 구성

#### Spring Boot (API + WebSocket)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-boot
  namespace: app
spec:
  replicas: 2
  progressDeadlineSeconds: 120  # 2분 내 배포 진행 없으면 실패 판정 (4.8 참조)
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

#### FastAPI (AI)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi
  namespace: app
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

### 4.3 배포 전략: Rolling Update

`maxSurge: 1, maxUnavailable: 0` 설정으로, 새 Pod가 Ready 상태가 된 후에야 기존 Pod를 제거합니다.
이를 통해 배포 중에도 가용 Pod 수가 줄어들지 않으며, 피크 시간대에도 안전하게 배포할 수 있습니다.

### 4.4 Probe 설계

| Probe | 역할 | 실패 시 동작 |
|-------|------|-------------|
| readinessProbe | 트래픽을 받을 준비가 되었는지 확인 | Service에서 해당 Pod로의 트래픽 제외 |
| livenessProbe | 프로세스가 정상 동작하는지 확인 | Pod 재시작 |

readinessProbe는 배포 직후 애플리케이션이 초기화되는 동안 트래픽이 유입되는 것을 방지합니다.
livenessProbe는 프로세스가 살아있지만 응답 불가(hang)인 상태를 감지하여 자동으로 재시작합니다.

#### 서비스별 Probe 설정

| 서비스 | Probe | 엔드포인트 | initialDelay | period | failureThreshold | 설정 이유 |
|--------|-------|-----------|-------------|--------|-----------------|-----------|
| Spring Boot | readiness | `GET /actuator/health:8080` | 30초 | 10초 | 3 | Spring 초기화(Bean, DB 커넥션 풀)에 시간 필요 |
| Spring Boot | liveness | `GET /actuator/health:8080` | 60초 | 15초 | 3 | 초기화 완료 후 시작, hang 감지 |
| FastAPI | readiness | `GET /health:8000` | 10초 | 10초 | 3 | Python 기동이 빠름 |
| FastAPI | liveness | `GET /health:8000` | 15초 | 15초 | 3 | AI 모델 로딩 후 시작 |

> Spring Boot의 `initialDelaySeconds`가 FastAPI보다 긴 이유는 Spring 컨텍스트 초기화(Bean 스캔, DB 커넥션 풀 생성 등)에 더 많은 시간이 걸리기 때문입니다. 실제 기동 시간은 클러스터 구성 후 측정하여 조정합니다.

### 4.5 Service 구성

```yaml
apiVersion: v1
kind: Service
metadata:
  name: spring-svc
  namespace: app
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
  namespace: app
spec:
  type: ClusterIP
  selector:
    app: fastapi
  ports:
    - port: 80
      targetPort: 8000
```

### 4.6 Ingress (ALB)

Caddy를 제거하고 ALB + AWS Load Balancer Controller로 외부 트래픽을 라우팅합니다.
정적 파일은 S3 + CloudFront(CDN)로 분리하고, ALB는 API 트래픽만 처리합니다.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: app
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

### 4.7 설정 관리

| 리소스 | 용도 | 소스 |
|--------|------|------|
| ConfigMap | 환경 설정 (프로필, 외부 URL 등) | Git 관리 |
| Secret | 민감 정보 (DB 비밀번호, API 키 등) | Sealed Secrets로 암호화하여 Git 관리 (6.5 참조) |

### 4.8 배포 실패 시 자동 보호 및 롤백

#### 4.8.1 자동 보호 메커니즘

4.3의 `maxUnavailable: 0`과 4.4의 readinessProbe가 조합되어, 새 Pod가 Probe를 통과하지 못하면 배포가 자연스럽게 **중단(stall)** 됩니다.
기존 Pod는 제거되지 않으므로 서비스에는 영향이 없습니다.

여기에 `progressDeadlineSeconds: 120` (4.2 Deployment에 설정)을 더하면, 2분 내 배포가 진행되지 않을 경우 Deployment 상태가 자동으로 `Progressing=False`로 전환되고, ArgoCD가 Degraded 상태로 표시하여 운영자에게 알립니다.

```
[정상 배포 흐름]
새 Pod 생성 → readinessProbe 통과 → Service에 등록 → 기존 Pod 제거 → 완료

[실패 배포 흐름]
새 Pod 생성 → readinessProbe 실패 반복 → Service에 등록되지 않음
  → maxUnavailable=0이므로 기존 Pod 제거 안 됨 (서비스 영향 없음)
  → progressDeadlineSeconds 초과 → Deployment 상태 "Progressing=False"
  → ArgoCD가 Degraded 상태로 표시 → 운영자에게 알림
```

#### 4.8.2 실패 감지 후 조치

배포가 `progressDeadlineSeconds`를 초과하여 실패 판정된 경우:

```bash
# 1. 배포 상태 확인 — "Progressing=False" 조건 확인
$ kubectl rollout status deployment/spring-boot -n app
# → "error: deployment "spring-boot" exceeded its progress deadline"

# 2. 실패한 새 Pod의 로그 확인
$ kubectl logs -l app=spring-boot -n app --tail=50

# 3. 이벤트 확인 — readinessProbe 실패 원인 파악
$ kubectl describe pod -l app=spring-boot -n app | grep -A5 "Events"

# 4. 직전 버전으로 롤백
$ kubectl rollout undo deployment/spring-boot -n app

# 5. 롤백 완료 확인
$ kubectl rollout status deployment/spring-boot -n app
```

> `kubectl rollout undo`는 긴급 대응용입니다. Git과 클러스터 상태가 불일치(OutOfSync)하므로, 이후 cloud-repo에서 `git revert`로 Git 상태를 동기화해야 합니다.

#### 4.8.3 배포 보호 흐름 요약

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

#### 4.8.4 자동 롤백을 도입하지 않는 이유

- readinessProbe + `maxUnavailable: 0`이 이미 서비스를 보호하므로, 운영자가 판단할 시간이 충분
- 배포 실패 원인이 코드가 아닌 일시적 외부 요인(DB 연결 지연, ConfigMap 누락 등)일 수 있어, 자동 revert는 불필요한 롤백을 유발할 수 있음
- Argo Rollouts(Canary/Blue-Green 기반 메트릭 자동 롤백)는 현재 구성(Deployment + ArgoCD) 대비 오버스펙. 규모가 커져 Canary 배포가 필요해지면 도입 검토

---

## 5. 스케일링 전략

### 5.1 HPA (Horizontal Pod Autoscaler)

피크 시간대 트래픽 급증에 Pod 단위로 자동 대응합니다.

#### Spring Boot HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: spring-boot-hpa
  namespace: app
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
  namespace: app
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

### 5.2 커스텀 메트릭 확장 (추후)

현재는 CPU 기반으로 시작하고, 운영 데이터가 쌓이면 Prometheus Adapter를 통해 커스텀 메트릭 기반 스케일링을 도입합니다.

| 단계 | 메트릭 | 도구 |
|------|--------|------|
| 1단계 (초기) | CPU Utilization | HPA 기본 |
| 2단계 (운영 후) | 요청 수, 응답 지연, WebSocket 연결 수 | Prometheus Adapter + HPA custom metrics |

### 5.3 Cluster Autoscaler는 도입하지 않음

워커 노드 4대를 고정 운영하고, Pod 레벨에서만 스케일링합니다.
현재 규모에서는 HPA만으로 피크 대응이 가능하며, 노드 자동 확장은 비용 대비 효과가 낮다고 판단했습니다.
규모가 커져 워커 4대로 부족해지는 시점에 Cluster Autoscaler 또는 Karpenter 도입을 검토합니다.

---

## 6. 배포 고도화 (Helm, ArgoCD)

### 6.1 Manifest 관리 방식

| 대상 | 관리 방식 | 이유 |
|------|-----------|------|
| 애플리케이션 (Spring, FastAPI) | 순수 YAML | 직접 작성하여 구조를 이해하고, 환경별 차이를 명확하게 관리 |
| 외부 스택 (ALB Controller, ArgoCD, Sealed Secrets) | Helm Chart | 복잡한 외부 도구를 안정적으로 설치·관리 |

### 6.2 환경 격리 방식

단일 클러스터 내에서 namespace로 환경을 분리합니다.

| 환경 | Namespace | 용도 |
|------|-----------|------|
| dev | `app-dev` | 개발·기능 테스트 |
| stg | `app-stg` | 통합 테스트·부하 테스트 |
| prod | `app-prod` | 운영 |

- NetworkPolicy로 namespace 간 트래픽을 차단하여 환경 간 간섭 방지
- ResourceQuota로 dev/stg가 prod의 리소스를 침범하지 않도록 제한
- 클러스터 분리나 AWS 계정 분리는 현재 규모 대비 비용/운영 부담이 과도하여 채택하지 않음

### 6.3 디렉토리 구조

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
    app-dev.yaml
    app-stg.yaml
    app-prod.yaml
```

- `base/`: 모든 환경에 공통인 리소스 정의
- `overlays/`: 환경별로 replicas, 이미지 태그, 리소스 제한 등을 Kustomize patch로 오버라이드
- `argocd/`: ArgoCD가 각 환경을 바라보는 Application CR 정의

### 6.4 ArgoCD

#### 6.4.1 GitOps 배포 방식

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

#### 6.4.2 멀티 레포 전략

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

#### 6.4.3 배포 파이프라인

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

#### 6.4.4 환경별 동기화 정책

| 환경 | 동기화 방식 | 이유 |
|------|------------|------|
| dev | **자동 동기화** (Auto Sync) | 매일 수회 배포, 빠른 피드백 필요 |
| stg | **수동 동기화** (Manual Sync) | 부하 테스트 등 진행 중 의도치 않은 배포 방지 |
| prod | **수동 동기화** (Manual Sync) | 클라우드 담당자가 ArgoCD UI에서 명시적으로 Sync 버튼 클릭 |

- dev: Git에 manifest가 반영되면 ArgoCD가 즉시 클러스터에 동기화
- stg/prod: Git에 manifest가 반영되어도 ArgoCD는 "OutOfSync" 상태만 표시. 클라우드 담당 2인 중 1인이 확인 후 수동으로 Sync 실행

#### 6.4.5 ArgoCD Application 예시 (prod)

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
    namespace: app
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

### 6.5 Secret 관리

#### 6.5.1 문제

GitOps에서는 모든 리소스를 Git에 저장하는 것이 원칙이지만, Secret(DB 비밀번호, API 키 등)은 평문으로 Git에 커밋할 수 없습니다.

#### 6.5.2 방식: Sealed Secrets

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
  namespace: app
spec:
  encryptedData:
    password: AgBy3i4OJSWK+PiTySYZZA9rO...  # 암호화된 값
```

#### 6.5.3 Sealed Secrets 선택 이유

| 방식 | 장점 | 단점 | 판정 |
|------|------|------|------|
| AWS SSM + ExternalSecrets | AWS 네이티브, Secret 중앙 관리 | ExternalSecrets Operator 추가 설치, AWS IAM 연동 필요 | 후보 |
| HashiCorp Vault | 강력한 접근 제어, 동적 시크릿 | 별도 Vault 클러스터 운영 필요, 과도한 복잡도 | 제외 |
| **Sealed Secrets** | **Git 단일 관리, 추가 인프라 불필요, 단순함** | **Secret 갱신 시 재암호화 필요** | **선택** |

- 현재 팀 규모(6인, 클라우드 2인)에서 Vault는 운영 부담이 과도함
- Sealed Secrets는 Git에 모든 것을 저장한다는 GitOps 원칙과 가장 잘 부합
- Secret 갱신이 빈번하지 않으므로 재암호화 비용이 낮음

---

## 7. 장애 대응 및 자동 복구

### 7.1 Pod 레벨

| 장애 유형 | 대응 | 설정 |
|-----------|------|------|
| 컨테이너 crash | 자동 재시작 | `restartPolicy: Always` (Deployment 기본값) |
| 프로세스 hang | liveness probe 실패 → 재시작 | `livenessProbe` (4.4 참조) |
| 배포 중 트래픽 유입 | readiness probe 통과 전 트래픽 제외 | `readinessProbe` (4.4 참조) |

### 7.2 WebSocket 연결 보호

```yaml
# Pod 종료 시 기존 연결을 정리할 시간 확보
terminationGracePeriodSeconds: 60
---
# 동시에 내려갈 수 있는 Pod 수 제한
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: spring-boot-pdb
  namespace: app
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: spring-boot
```

배포나 노드 유지보수 시에도 최소 1개의 Spring Boot Pod가 항상 유지되어 WebSocket 연결이 전부 끊어지는 상황을 방지합니다.

### 7.3 노드 레벨

| 장애 유형 | K8s 자동 대응 |
|-----------|--------------|
| 워커 노드 1대 장애 | 해당 노드의 Pod를 다른 노드로 자동 재스케줄링 (N+1 설계로 수용 가능) |
| 마스터 노드 1대 장애 | etcd 쿼럼 유지 (3대 중 2대 생존), API Server는 NLB가 정상 노드로 라우팅 |
| 마스터 노드 2대 장애 | etcd 쿼럼 상실 → 컨트롤플레인 중단 (기존 Pod는 계속 동작, 새 배포/스케일링 불가) |

### 7.4 etcd 백업

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

## 8. 클러스터 구성도

```
                         ┌──────────────────┐
                         │    Cloudflare     │
                         └────────┬─────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
            ┌───────▼───────┐          ┌────────▼────────┐
            │  CloudFront   │          │   ALB (public)  │
            │  + S3 (정적)  │          │   /api, /ai     │
            └───────────────┘          └────────┬────────┘
                                                │
                              ┌─────────────────┼─────────────────┐
                              │         K8s Cluster               │
                              │                                   │
                              │  ┌─── Master (HA, 3대) ────────┐ │
                              │  │ etcd, apiserver, scheduler,  │ │
                              │  │ controller-manager           │ │
                              │  │         ↕ NLB               │ │
                              │  └──────────────────────────────┘ │
                              │                                   │
                              │  ┌─── Worker (4대, 2AZ) ───────┐ │
                              │  │                              │ │
                              │  │  ┌─────────┐ ┌───────────┐  │ │
                              │  │  │ Spring  │ │  FastAPI   │  │ │
                              │  │  │ Boot    │ │  (AI)      │  │ │
                              │  │  │ ×2~4    │ │  ×1~2      │  │ │
                              │  │  └────┬────┘ └─────┬─────┘  │ │
                              │  │       │            │         │ │
                              │  │  spring-svc    fastapi-svc   │ │
                              │  │  (ClusterIP)   (ClusterIP)   │ │
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
API 요청:   User → Cloudflare → ALB → Ingress → spring-svc → Spring Pods
AI 요청:    User → Cloudflare → ALB → Ingress → fastapi-svc → FastAPI Pods
내부 통신:  Spring Pods → fastapi-svc (ClusterIP, DNS)
DB 접근:    Spring Pods → RDS (외부, Private Subnet)
```

---

## 9. 설정 명세

### 9.1 kubeadm 초기화

```bash
# 첫 번째 마스터 노드
kubeadm init \
  --control-plane-endpoint "<NLB_DNS>:6443" \
  --upload-certs \
  --pod-network-cidr=10.244.0.0/16

# 추가 마스터 노드 (2, 3번)
kubeadm join <NLB_DNS>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <CERT_KEY>

# 워커 노드
kubeadm join <NLB_DNS>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

### 9.2 주요 파라미터

| 항목 | 값 |
|------|-----|
| Kubernetes 버전 | v1.34.x |
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 (기본값) |
| API Server 엔드포인트 | NLB DNS:6443 |
| 컨테이너 런타임 | containerd |

### 9.3 서비스별 명세

| 서비스 | 이미지 | 포트 | replicas (평시) | replicas (피크) | CPU req/limit | Memory req/limit |
|--------|--------|------|----------------|----------------|---------------|-----------------|
| Spring Boot | ECR/spring-boot | 8080 | 2 | 4 | 500m / 1000m | 1Gi / 2Gi |
| FastAPI | ECR/fastapi | 8000 | 1 | 2 | 500m / 1000m | 512Mi / 1Gi |
| ArgoCD | argoproj/argocd | 8080 | 1 | 1 | 200m / 500m | 256Mi / 512Mi |

---

## 10. 운영 시나리오

### 10.1 피크 시간대 자동 확장

```
12:00 점심 피크 시작
  → Spring Boot CPU 사용률 70% 초과
  → HPA가 감지 → replicas 2 → 3 → 4 (수십 초 이내)
  → 새 Pod가 readinessProbe 통과 후 트래픽 수신 시작

13:30 피크 종료
  → CPU 사용률 하락
  → HPA cooldown 후 replicas 4 → 3 → 2 (점진적 축소)
```

### 10.2 워커 노드 장애

```
워커 노드 1대 (2a) 장애 발생
  → 해당 노드의 Pod가 NotReady 상태
  → K8s controller가 5분 내 다른 노드로 Pod 재스케줄링
  → 남은 3대(2a×1, 2c×2)로 피크 트래픽 수용 가능 (N+1 설계)
  → 장애 노드 복구 후 Pod가 자동으로 재분배
```

### 10.3 롤링 배포

```
새 버전 배포 시작
  → ArgoCD가 Git의 이미지 태그 변경 감지
  → maxSurge=1: 새 Pod 1개 생성
  → 새 Pod의 readinessProbe 통과 확인
  → maxUnavailable=0: 기존 Pod 1개 제거
  → 위 과정을 replica 수만큼 반복
  → WebSocket 사용자: terminationGracePeriodSeconds(60초) 동안 기존 연결 유지 후 종료
  → 전체 과정에서 가용 Pod 수가 줄어들지 않음

배포 실패 시:
  → readinessProbe 실패 → 기존 Pod 유지 → 서비스 무영향 (상세: 4.8 참조)
```

### 10.4 마스터 노드 장애

```
마스터 1대 장애
  → etcd 쿼럼 유지 (2/3 생존)
  → NLB가 정상 API Server로 라우팅
  → kubectl, HPA, 배포 모두 정상 동작
  → 장애 노드 복구 후 etcd 자동 동기화

마스터 2대 장애 (극단적 상황)
  → etcd 쿼럼 상실 → 컨트롤플레인 중단
  → 기존 Pod는 계속 동작 (서비스 유지)
  → 새 배포, 스케일링, Pod 재스케줄링 불가
  → etcd 스냅샷으로 복구
```
