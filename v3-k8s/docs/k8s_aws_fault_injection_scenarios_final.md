# Kubernetes / AWS 고가용성 Fault Injection 시나리오

> kubeadm + Multi-AZ + NLB + External RDS/Redis 운영 기준

## 문서 개요

| 항목 | 내용 |
|---|---|
| 문서 목적 | 멀티 AZ + kubeadm HA 구조에서 어떤 장애를 주입하고 무엇을 증명해야 하는지 운영 관점으로 정리 |
| 기준 환경 | Track B: control-plane 3대, worker 4대, public ingress NLB, internal API NLB, external RDS / Redis |
| 작성 기준일 | 2026-03-18 |
| 근거 문서 | kubeadm Prod VPC Runbook / 05-kubeadm 설계 문서 |
| 사용처 | 운영 리허설, 장애 훈련, HA 증빙, 인수인계 |

> **핵심 원칙**  
> 각 실험은 `가설 - 주입 - 관측 - 판정 - 롤백` 형식으로 남긴다. 결과는 단순 성공 / 실패가 아니라 실제 사용자 영향, unhealthy 전환 시간, recovery 시점을 포함해야 한다.

---

## 1. 대상 아키텍처와 실험 목표

실험 범위는 운영형 **Track B 토폴로지**를 기준으로 고정한다.

| 구성 요소 | 운영 기준 |
|---|---|
| Control-plane | kubeadm control-plane 3대, etcd quorum 2/3 유지 |
| Worker | t3.medium 4대, 2a x2 / 2b x1 / 2c x1 분산 |
| API 진입점 | internal NLB -> kube-apiserver : 6443/TCP |
| 서비스 진입점 | public NLB -> ingress-nginx NodePort 30080/30443 -> ClusterIP |
| 상태 저장 계층 | 클러스터 외부 RDS / Redis 유지 |
| 핵심 목표 | worker 1대 손실 무중단, control-plane 1대 손실 시 API 지속, AZ 일부 손실 시 서비스 유지 |

### 이 문서에서 증명하려는 것

1. worker / ingress 장애 흡수
2. control-plane 1대 손실에도 `kubectl` / rollout / HPA 지속
3. AZ 단위 손실 내성
4. RDS / Redis 같은 외부 의존성 장애 격리
5. bad rollout, websocket, HPA, etcd backup/restore까지 포함한 운영 복구 가능성

---

## 2. 실험 운영 원칙

작은 blast radius부터 시작해 점진적으로 확장한다.

- **P0부터 시작한다.**  
  `worker drain -> worker hard stop -> control-plane 1대 stop -> AZ 장애 시뮬레이션` 순서가 기본이다.
- 각 실험 전 baseline을 남긴다.  
  노드 / Pod 상태, NLB target health, 주요 health endpoint, 5xx, latency를 캡처한다.
- 허용 임계치(예: 5xx 2% 초과, 사용자 영향 3분 이상)를 넘으면 즉시 중단하고 롤백한다.
- 주입은 운영과 유사한 수단을 사용한다.  
  drain, EC2 stop, egress 차단, 잘못된 이미지 태그, 부하 발생기를 우선 사용한다.

---

## 3. 공통 관측 지표

실험마다 최소한 아래 항목은 공통으로 남긴다.

| 관측 축 | 필수 항목 | 의미 |
|---|---|---|
| 가용성 | HTTP 성공률, 5xx | 사용자 영향 확인 |
| 지연 | p50 / p95 / p99 | 장애 흡수 중 성능 저하 확인 |
| 재스케줄 | eviction / reschedule 시간 | 노드 손실 흡수 능력 |
| 진입면 | NLB target health | 외부 경로 유지 여부 |
| 제어면 | `kubectl`, `cluster-info`, rollout, HPA | control-plane 가용성 |
| 연결성 | DB 5432, Redis 6379, websocket reconnect | 외부 의존성과 장기 연결 품질 |
| 복구 | 정상 복귀까지 소요 시간 | RTO 관점 검증 |

---

## 4. 권장 실행 순서

아래 순서대로 진행하면 리스크를 통제하면서 고가용성 검증 범위를 넓힐 수 있다.

| ID | 우선순위 | 시나리오 | 주요 증명 포인트 |
|---|---|---|---|
| FI-01 | P0 | Worker drain | 계획된 유지보수 무중단 |
| FI-02 | P0 | Worker hard stop | 비정상 노드 손실 흡수 |
| FI-03 | P0 | Control-plane 1대 stop | etcd quorum / API 지속 |
| FI-04 | P0 | AZ 2b 장애 시뮬레이션 | 멀티 AZ 내성 |
| FI-05 | P1 | Ingress replica 장애 | 진입면 부분 장애 흡수 |
| FI-06 | P1 | RDS / Redis 연결 차단 | 외부 의존성 격리 |
| FI-07 | P1 | Bad rollout + undo | 배포 실패 보호 / 복구 |
| FI-08 | P1 | HPA scale-out under load | 확장 유효성 |
| FI-09 | P1 | WebSocket 장기 연결 보호 | 배포 / drain 중 연결 안정성 |
| FI-10 | P2 | etcd snapshot / restore rehearsal | 복구 가능성 |

---

## 5. 상세 시나리오

운영 리허설 문서에 바로 넣을 수 있도록 목적, 주입, 지표, 통과 기준, 롤백 항목까지 포함한다.

### FI-01. Worker drain - 계획된 유지보수 시 무중단 확인

가장 먼저 수행해야 하는 기본 시나리오다. 런북의 운영 드릴과 직접 연결되며, drain 상황에서 Spring / FastAPI가 다른 worker로 재배치되고 외부 트래픽이 계속 성공해야 한다.

- **목적**  
  계획된 유지보수(커널 패치, 노드 점검, 재부팅) 중에도 서비스가 중단되지 않는지 검증한다.
- **장애 주입**  
  `kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data`  
  예시 대상: `prod-ec2-k8s-worker-2b`
- **예상 동작**
  - app-prod 워크로드가 다른 worker로 재스케줄된다.
  - public NLB / ingress 경로는 healthy 상태를 유지한다.
  - `/api`, `/ai`, `/ws` 모두 사용 가능해야 한다.
- **관측 지표**
  - `kubectl get pods -n app-prod -o wide`
  - NLB target health
  - HTTP 5xx 비율, p95 latency
  - 재스케줄 완료 시간
- **통과 기준**
  - 사용자 체감 중단이 없다.
  - 핵심 health endpoint 성공률이 유지된다.
  - drain 종료 후 workload가 다른 worker에서 Ready 상태로 전환된다.
  - 오류율 spike가 허용 범위 이내다.
- **롤백 / 복구**
  - `kubectl uncordon <worker>`
  - 필요 시 drain 중단 후 PDB / request / anti-affinity 설정 조정
- **증적 캡처**
  - drain 시작 시각, eviction 완료 시각, 새 Pod Ready 시각
  - pod 분포 전후 비교 캡처
  - health check 및 5xx 그래프

```bash
kubectl drain prod-ec2-k8s-worker-2b --ignore-daemonsets --delete-emptydir-data
kubectl get pods -n app-prod -o wide
```

---

### FI-02. Worker hard stop - 비정상 노드 손실 흡수

실제 장애는 drain처럼 예쁘게 오지 않는다. EC2 stop 또는 네트워크 단절처럼 "갑자기 사라지는" worker를 클러스터가 얼마나 흡수하는지 본다.

- **목적**  
  노드 비정상 종료, 인스턴스 장애, 커널 패닉 등 hard failure 상황에서 데이터플레인이 유지되는지 확인한다.
- **장애 주입**
  - `aws ec2 stop-instances --instance-ids <WORKER_INSTANCE_ID>`
  - 또는 해당 노드 네트워크 차단
- **예상 동작**
  - 노드가 `NotReady`로 전환된다.
  - 기존 Pod는 다른 worker에 재배치된다.
  - NLB는 unhealthy target을 회피해야 한다.
  - 남은 worker capacity로 최소 서비스 유지가 가능해야 한다.
- **관측 지표**
  - node `NotReady` 전환 시간
  - unhealthy target 전환 시각
  - 새 Pod Ready 시각
  - HTTP 성공률 / 5xx / latency
- **통과 기준**
  - hard failure 후에도 API health check가 계속 성공한다.
  - 대규모 5xx 급증이 없다.
  - 재스케줄이 제한된 시간 내 완료된다.
- **롤백 / 복구**
  - `aws ec2 start-instances --instance-ids <WORKER_INSTANCE_ID>`
  - 복구 후 `kubectl wait --for=condition=Ready node/<worker>`
- **증적 캡처**
  - stop 시각, NLB unhealthy 전환 시각, recovery 완료 시각
  - 노드 상태 전이 캡처
  - 외부 health check 결과

```bash
aws ec2 stop-instances --instance-ids <WORKER_INSTANCE_ID>
kubectl get nodes -w
kubectl get pods -n app-prod -o wide
```

---

### FI-03. Control-plane 1대 stop - kubeadm HA 증명

멀티 AZ kubeadm을 썼다면 가장 중요한 시험 중 하나다. control-plane 1대 손실에서도 quorum이 유지되고 `kubectl`, rollout, HPA가 계속 동작해야 한다.

- **목적**  
  etcd quorum과 API endpoint 지속성을 검증한다.
- **장애 주입**
  - `aws ec2 stop-instances --instance-ids <CP_2B_INSTANCE_ID>`
  - 대상 예시: `prod-ec2-k8s-cp-2b`
- **예상 동작**
  - 나머지 2대 control-plane이 quorum을 유지한다.
  - `kubectl get nodes` / `cluster-info` / rollout / HPA 조회가 계속 동작한다.
  - internal API NLB는 healthy target만 사용한다.
- **관측 지표**
  - `kubectl get nodes`
  - `kubectl cluster-info`
  - NLB 6443 target health
  - etcd member health
  - apiserver 응답 시간
- **통과 기준**
  - API endpoint가 중단되지 않는다.
  - 새 배포나 HPA 동작이 막히지 않는다.
  - 복구 후 해당 노드가 다시 Ready로 돌아온다.
- **롤백 / 복구**
  - `aws ec2 start-instances --instance-ids <CP_2B_INSTANCE_ID>`
  - `kubectl wait --for=condition=Ready node/prod-ec2-k8s-cp-2b`
- **증적 캡처**
  - stop / start 시각
  - kubectl 지속 동작 캡처
  - NLB target health
  - 복구 시점

```bash
aws ec2 stop-instances --instance-ids <CP_2B_INSTANCE_ID>
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

---

### FI-04. AZ 2b 장애 시뮬레이션 - 멀티 AZ 내성 본시험

문서상 설계 목표는 AZ 일부 손실에도 서비스가 남은 AZ로 버티는 것이다. 가장 현실적인 방법은 2b의 control-plane + worker를 함께 stop하여 AZ 손실을 가정하는 것이다.

- **목적**  
  2b 가용 영역 손실 시에도 control-plane 2대, worker 3대 생존으로 서비스가 유지되는지 검증한다.
- **장애 주입**
  - `cp-2b + worker-2b` 동시 stop
  - 필요 시 2b subnet routing / NACL 차단으로 강화
- **예상 동작**
  - etcd quorum 유지
  - 남은 worker 3대로 서비스 지속
  - public NLB와 internal API NLB 모두 healthy target만 사용
  - 배포 / HPA / health check 정상
- **관측 지표**
  - 생존 노드 수
  - NLB target health 변화
  - HTTP 성공률
  - latency
  - 새 배포 가능 여부
  - HPA 상태
- **통과 기준**
  - 외부 요청이 계속 성공하고, API endpoint도 유지된다.
  - 남은 worker capacity로 핵심 서비스가 계속 동작한다.
  - Failover 후 수동 개입 없이 안정화된다.
- **롤백 / 복구**
  - 중지한 인스턴스 재기동 또는 네트워크 차단 해제
  - 복구 후 모든 node Ready / target healthy 확인
- **증적 캡처**
  - 장애 주입 전후 노드 분포
  - NLB healthy 수
  - 오류율 그래프
  - 복구 완료 시각

```bash
aws ec2 stop-instances --instance-ids <CP_2B_INSTANCE_ID> <WORKER_2B_INSTANCE_ID>
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

---

### FI-05. Ingress controller replica 장애 - 진입면 부분 장애 흡수

서비스가 살아 있어도 ingress replica가 줄면 외부 라우팅이 깨질 수 있다. NodePort + public NLB 구조에서 ingress-nginx 부분 장애를 따로 확인해야 한다.

- **목적**  
  ingress controller pod 또는 해당 worker 손실 시 외부 진입 경로가 유지되는지 검증한다.
- **장애 주입**
  - `kubectl delete pod -n ingress-nginx <controller-pod>`
  - 또는 ingress가 올라간 worker 1대 drain / stop
- **예상 동작**
  - 다른 ingress replica가 외부 트래픽을 계속 처리한다.
  - NLB unhealthy target은 우회된다.
  - `/api`, `/ai`, `/ws`의 응답 성공률이 유지된다.
- **관측 지표**
  - ingress-nginx Ready replica 수
  - NLB 30080 / 30443 target health
  - HTTP 5xx / latency
  - websocket reconnect 비율
- **통과 기준**
  - replica 하나 손실에도 외부 요청이 계속 성공한다.
  - NLB가 unhealthy target을 회피한다.
  - controller replica가 재생성된다.
- **롤백 / 복구**
  - 삭제한 pod는 자동 복구를 확인
  - 노드 장애 실험이었다면 `uncordon` 또는 인스턴스 재기동
- **증적 캡처**
  - pod 삭제 시각
  - replica 복구 시각
  - target health 변화
  - 외부 health 결과

```bash
kubectl get pods -n ingress-nginx -o wide
kubectl delete pod -n ingress-nginx <controller-pod>
aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>
```

---

### FI-06. RDS / Redis 연결 차단 - 외부 의존성 장애 격리

클러스터가 멀쩡해도 외부 DB / Redis 경로가 끊기면 서비스는 장애가 된다. 목표는 "전체 장애"가 아니라 "문제 Pod 격리"인지 확인하는 것이다.

- **목적**  
  RDS / Redis 네트워크 문제 시 readiness와 에러 처리 전략이 전체 서비스 장애로 번지지 않는지 확인한다.
- **장애 주입**
  - 특정 worker 또는 특정 canary pod에 대해 5432 / 6379 egress 차단
  - 예: `iptables DROP`, SG 변경, network policy, `tc netem`
- **예상 동작**
  - 연결 불가 Pod는 timeout 또는 fail-fast 후 readiness에서 제외된다.
  - healthy Pod는 계속 serving 한다.
  - 전체 서비스 5xx는 제한적이어야 한다.
- **관측 지표**
  - DB / Redis 연결 실패 로그
  - readiness 변화
  - healthy / unhealthy pod 수
  - API 오류율 / latency
- **통과 기준**
  - 장애가 일부 Pod 수준에서 격리된다.
  - 전체 서비스 성공률이 크게 무너지지 않는다.
  - 복구 후 정상 연결로 되돌아간다.
- **롤백 / 복구**
  - 차단 규칙 해제, SG 원복, `iptables flush`
  - 필요 시 문제 pod 재시작
- **증적 캡처**
  - 차단 적용 시각
  - readiness 변화
  - DB / Redis 연결 실패 로그
  - 복구 후 정상 health

```bash
kubectl logs -n app-prod -l app=spring-boot --tail=100
kubectl get pods -n app-prod -w
# 실제 차단은 canary 범위에서만 수행
```

---

### FI-07. Bad rollout + undo - 배포 실패 보호 및 복구

readiness / PDB / rollout undo가 실제로 운영 안전장치로 작동하는지 봐야 한다. 잘못된 이미지 태그, 잘못된 env, 깨진 config가 대표적 주입 수단이다.

- **목적**  
  배포 실패가 전체 장애로 번지지 않고, 운영자가 짧은 시간 안에 이전 상태로 되돌릴 수 있는지 검증한다.
- **장애 주입**
  - 잘못된 이미지 태그 또는 의도적으로 readiness를 통과하지 못하는 설정으로 배포
  - 이후 `kubectl rollout undo` 또는 Git revert
- **예상 동작**
  - 새 Pod는 Ready가 되지 못하고 기존 Pod는 유지된다.
  - 서비스 영향은 제한적이어야 한다.
  - undo 후 이전 버전으로 정상 복귀한다.
- **관측 지표**
  - Deployment condition
  - Ready replica 수
  - 5xx / latency
  - undo 완료 시간
- **통과 기준**
  - 잘못된 배포가 전체 장애를 만들지 않는다.
  - undo 후 서비스가 정상 복구된다.
  - ArgoCD / rollout 상태가 다시 Healthy / Synced로 돌아온다.
- **롤백 / 복구**
  - `kubectl rollout undo deployment/<name> -n app-prod`
  - 또는 cloud-repo 이미지 태그 revert 후 ArgoCD sync
- **증적 캡처**
  - 실패 rollout 상태
  - 이벤트 로그
  - undo 시각
  - 복구 완료 시각
  - 사용자 영향 범위

```bash
kubectl rollout status deployment/spring-boot -n app-prod
kubectl describe pod -l app=spring-boot -n app-prod
kubectl rollout undo deployment/spring-boot -n app-prod
```

---

### FI-08. HPA scale-out under load - 피크 대응 검증

k8s를 도입한 이유 중 하나가 피크 시간대 수십 초 단위 확장이다. 부하를 걸었을 때 HPA가 실제로 replica를 늘리고 latency를 안정화하는지 확인해야 한다.

- **목적**  
  CPU 기반 HPA가 부하 증가를 감지하고 적절히 scale-out 하는지 검증한다.
- **장애 주입**
  - `hey` 등으로 2~5분 부하 생성
  - 가능하면 worker 1대 손실 상태와 조합해 수행
- **예상 동작**
  - `spring-boot-hpa`가 2 -> 3 -> 4로 증가한다.
  - metrics server 값이 정상 수집된다.
  - 증설 후 latency가 안정화된다.
- **관측 지표**
  - `kubectl get hpa -w`
  - `kubectl top pods`
  - `kubectl top nodes`
  - HTTP latency / error rate
- **통과 기준**
  - HPA가 기대한 replica 범위로 증가한다.
  - scale-out 이후 오류율이 낮게 유지된다.
  - worker 1대 손실 상태에서도 최소 목표 성능을 충족한다.
- **롤백 / 복구**
  - loadgen 중지 후 HPA가 안정화될 때까지 관찰
  - 필요 시 HPA threshold / request 조정
- **증적 캡처**
  - 부하 시작 시각
  - replica 증가 시각
  - 최대 replica
  - latency 변화 그래프

```bash
kubectl run loadgen -n app-prod --rm -it --restart=Never --image=rakyll/hey -- \
  -z 120s -c 40 http://spring-boot-svc/actuator/health
kubectl get hpa -w
kubectl top pods -n app-prod
```

---

### FI-09. WebSocket 장기 연결 보호 - rollout / drain 중 연결 안정성

이 구조에서 중요한 건 HTTP health만이 아니다. 배포나 drain 중에 장기 연결이 짧게 끊기면 사용자 체감이 크기 때문에 websocket을 별도로 검증해야 한다.

- **목적**  
  `terminationGracePeriod`, PDB, NGINX timeout 설정이 배포 / drain 중 websocket 연결을 보호하는지 검증한다.
- **장애 주입**
  - 웹소켓 클라이언트를 연결한 상태에서 rolling update 또는 worker drain 수행
- **예상 동작**
  - handshake는 지속 가능해야 한다.
  - 연결이 끊기더라도 reconnect 폭증 없이 제한적이어야 한다.
  - 배포 중 모든 연결이 한 번에 끊기지 않아야 한다.
- **관측 지표**
  - handshake 성공 여부
  - 연결 유지 시간
  - reconnect 비율
  - rollout 중 5xx
  - disconnect 이벤트
- **통과 기준**
  - 배포 / drain 중 대량 disconnect가 없다.
  - 사용자 영향이 허용 범위 이내다.
  - heartbeat / timeout 체인이 의도대로 동작한다.
- **롤백 / 복구**
  - rollout 중단 또는 undo
  - 드레인 중단 후 `uncordon`
  - heartbeat / timeout / ingress 설정 조정
- **증적 캡처**
  - websocket client 로그
  - disconnect / reconnect 횟수
  - rollout 이벤트 타임라인

```bash
curl -i --http1.1 \
  -H 'Host: tasteam.kr' \
  -H 'Connection: Upgrade' \
  -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==' \
  -H 'Sec-WebSocket-Version: 13' \
  https://tasteam.kr/ws
```

---

### FI-10. etcd snapshot / restore rehearsal - 운영자 복구 가능성 검증

kubeadm HA의 마지막 안전망은 etcd 백업 / 복원이다. "백업 파일이 있다"가 아니라 "실제로 snapshot이 유효하고 restore 경로를 설명할 수 있다"를 증명해야 한다.

- **목적**  
  정기 snapshot이 유효하며, 컨트롤플레인 장애 시 복구 절차가 재현 가능한지 검증한다.
- **장애 주입**
  - `ETCDCTL_API=3 etcdctl snapshot save ...`
  - snapshot status 확인
  - 가능하면 별도 테스트 control-plane에서 restore rehearsal
- **예상 동작**
  - snapshot 생성 / 업로드 성공
  - snapshot status 정상
  - 복원 절차 문서와 소요 시간 추정 가능
- **관측 지표**
  - snapshot 생성 시간
  - snapshot status 결과
  - S3 업로드 성공 여부
  - restore rehearsal 소요 시간
- **통과 기준**
  - 백업 파일이 유효하다.
  - restore runbook이 실행 가능한 수준으로 정리된다.
  - 복구 시 필요한 아티팩트와 명령이 모두 확인된다.
- **롤백 / 복구**
  - 테스트 복원 환경 정리
  - 운영 클러스터에는 snapshot 생성 외 직접 복원 작업을 수행하지 않는다.
- **증적 캡처**
  - snapshot status 캡처
  - S3 업로드 로그
  - restore rehearsal 메모
  - 예상 RTO

```bash
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-verify.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

---

## 6. 권장 실험 패키지

실험 난이도와 리스크에 따라 패키지로 묶어 운영하면 편하다.

| 패키지 | 포함 시나리오 | 권장 시점 |
|---|---|---|
| 기본 | FI-01, FI-02, FI-03 | 초기 리허설 / 월간 점검 |
| 고가용성 | FI-04, FI-05, FI-08, FI-09 | 배포 전 / 분기별 리허설 |
| 복구 | FI-06, FI-07, FI-10 | 변경 직후 / 반기별 |

---

## 7. 실험 결과에 반드시 남길 필드

표 전체를 만들지 않더라도 아래 항목은 빠지면 안 된다.

- 실험명 / 일시 / 담당자
- 가설과 사전 조건
- 장애 주입 방법과 정확한 시각
- 실제 결과: 오류율, latency, unhealthy 전환 시간, recovery 시각
- 판정: Pass / Fail / Partial
- 후속 조치: 설정 수정, 용량 증설, probe / PDB / HPA 조정

---

## 8. 근거 문서

본 문서는 아래 설계·운영 문서를 기반으로 정리되었다.

- `kubeadm Prod VPC Runbook`  
  Track A / Track B 토폴로지, NLB 경로, 운영 드릴, 백업 절차
- `05-kubeadm` 오케스트레이션 설계 문서  
  HA 목표, N+1 worker 산정, WebSocket / ingress / HPA 배경, 다중 AZ 설계 근거
