# v3 Spring Boot 롤아웃 실패 복합 이슈 트러블슈팅

- 날짜: 2026-03-25
- 영향 범위: app-prod namespace, spring-boot Deployment (replicas: 2)

## 증상

- 새 ReplicaSet 롤아웃 시 파드가 CrashLoopBackOff 반복
- startupProbe 실패 (HTTP 502), 파드 Killing → BackOff 루프
- ArgoCD UI에서 163건의 이벤트 누적
- 기존 RS의 파드 1개만 살아있는 상태

## 원인 분석

### 이슈 1: RecommendationBusinessException으로 앱 크래시 (근본 원인)

- `ApplicationReadyEvent` 리스너 `RecommendationImportPollingScheduler.pollAndImportOnStartup()` 실행
- S3에서 추천 결과를 폴링 → DB checkpoint 테이블에서 중복 확인 → 이미 import된 경우 예외 발생
- 예외가 `SpringApplication.run()`까지 전파 → `Application run failed` → 프로세스 종료

```
RecommendationBusinessException: 이미 import 완료된 추천 결과입니다.
dedupKey=deepfm-1.0.20260310124158+2026-03-25
```

- **멱등성 부재**: 첫 번째 파드가 import 성공 후, 두 번째 파드가 같은 데이터를 import 시도하면 예외 → 크래시
- replicas: 2인데 하루에 1개 파드만 살아남을 수 있는 구조
- 앱이 죽으면서 Redis/JPA 연결도 셧다운 → 스케줄러들이 이미 닫힌 커넥션에 접근 → 연쇄 에러 (`LettuceConnectionFactory is STOPPING`, `Session/EntityManager is closed`)

**해결**: 백엔드 팀에 전달 → 중복 import 시 예외 대신 skip 처리하도록 수정 적용

### 이슈 2: Kafka 브로커 연결 실패

- bootstrap.servers: `10.12.143.218:29092` (10.12.x.x VPC, Kafka 전용)
- k8s 클러스터: `10.11.x.x` VPC
- Spring Boot 파드에서 Kafka 브로커로 연결 시 지속적으로 disconnected

```
Bootstrap broker 10.12.143.218:29092 (id: -1 rack: null) disconnected
TimeoutException: Topic evt.user-activity.s3-ingest.v1 not present in metadata after 60000 ms.
```

#### 확인한 것들

| 항목 | 결과 |
|------|------|
| VPC 피어링 (10.11 ↔ 10.12) | 정상 (`pcx-00576c6dab258fc57`) |
| K8s VPC 라우팅 → 10.12.0.0/16 | 정상 (private RT에 피어링 경로 있음) |
| Kafka VPC 리턴 경로 → 10.11.0.0/16 | 정상 |
| Kafka SG 인바운드 29092 | 정상 (`10.11.0.0/16` 허용) |
| 워커 노드 → Kafka nc 테스트 | 4개 노드 전부 성공 |
| Kafka 브로커 상태 | 정상 (매시간 KRaft 스냅샷 생성) |
| 토픽 존재 여부 | `evt.user-activity.s3-ingest.v1` 존재 |
| advertised.listeners | `PLAINTEXT://10.12.143.218:29092` (IP 직접 사용, DNS 이슈 아님) |
| 파드 내부 → Kafka nc 테스트 | 타임아웃 (연결 불가) |

#### 원인: Linkerd sidecar가 Kafka 트래픽을 L7 프록시로 가로챔

- Linkerd는 HTTP/gRPC 전용 L7 프록시 — Kafka 바이너리 프로토콜을 해석하지 못함
- `linkerd-init`이 iptables로 모든 outbound를 프록시로 리다이렉트
- 워커 노드에서 nc 성공 / 파드 안에서 nc 실패의 원인
- skip-outbound-ports 적용 전: API_VERSIONS 핸드셰이크에서 ~1초 만에 끊김
- skip-outbound-ports 적용 후: 30초 소켓 연결 타임아웃으로 변경 (Linkerd 우회는 되었으나 여전히 연결 불가)

**조치 1**: `config.linkerd.io/skip-outbound-ports: "29092"` 어노테이션 추가 → Linkerd 우회 성공, 그러나 여전히 타임아웃

**조치 2**: `spring-boot-egress` NetworkPolicy에 Kafka egress 규칙 추가 → **해결**
- NetworkPolicy가 화이트리스트 방식이라 `10.12.0.0/16:29092`가 허용 목록에 없어서 Calico가 패킷을 드롭하고 있었음
- Linkerd skip만으로는 해결 불가 — Linkerd 뒤에 Calico NetworkPolicy라는 두 번째 벽이 있었음

```yaml
# networkpolicy.yaml (spring-boot-egress)
- to:
    - ipBlock:
        cidr: 10.12.0.0/16
  ports:
    - protocol: TCP
      port: 29092
```

### 이슈 3: Worker SG에 TCP 8443 누락 (선행 이슈)

- admission webhook 타임아웃으로 ingress-nginx가 1 replica로 축소된 상태에서 발견
- CP → Worker 방향 TCP 8443이 Worker SG에 없었음
- Calico `vxlanMode: CrossSubnet` — 같은 서브넷은 직접 라우팅 (SG가 실제 포트를 검사)

**해결**: `aws ec2 authorize-security-group-ingress --group-id sg-02e79d4f2cea3074f --protocol tcp --port 8443 --source-group sg-0e38c28205fe3e330`

### 이슈 4: S3 analytics 버킷 IAM 권한 누락

- `prod-spring-s3-upload` IAM 유저 정책에 analytics 버킷 ARN 누락
- `AccessDenied: s3:ListBucket on arn:aws:s3:::tasteam-prod-analytics`

**해결**: Terraform IAM 정책에 `aws_s3_bucket.analytics.arn` 추가 → apply

### 이슈 5: liveness probe가 startup 도중 파드를 죽임

- Spring Boot 부팅 ~95초 vs liveness 데드라인 ~105초 (initialDelaySeconds 60 + 15×3)
- 부팅 지연 시 liveness 실패 → SIGTERM(exit 143) → CrashLoopBackOff

**해결**: startupProbe 추가 (10s × 18 = 180초), initialDelaySeconds 제거, progressDeadlineSeconds 300으로 증가

### 이슈 6: IMDS 접근 불가 (Linkerd 가로챔)

- 파드에서 `169.254.169.254:80` 접근 시 Linkerd 프록시가 가로챔
- `l5d-proxy-error: endpoint 169.254.169.254:80: client error (Connect)`
- `config.linkerd.io/skip-outbound-ips`는 Linkerd에 존재하지 않는 어노테이션
- `skip-outbound-ports: "80"`은 클러스터 내부 HTTP 80 통신까지 skip → 부적절

**현재 상태**: IAM 정적 키(AccessKey/SecretKey)로 S3 접근하는 방식으로 우회. IMDS 직접 접근은 미해결.

## SSM 파라미터 추가

AI 서비스 연동을 위한 SSM 파라미터 등록:

| 파라미터 | 값 | 비고 |
|----------|-----|------|
| `/prod/tasteam/backend/AI_BASE_URL` | `http://fastapi-svc` | K8s 내부 DNS (같은 namespace) |
| `/prod/tasteam/backend/AI_RESPONSE_TIMEOUT` | `30s` | Spring 기본값과 동일 |

- Terraform `main.tf`에 파라미터 정의 추가 → apply → SSM에 실제 값 주입
- ExternalSecrets → `spring-boot-runtime` Secret → 파드 환경변수로 주입

## 진단 명령어 모음

```bash
# 워커 노드에서 Kafka 연결 테스트 (SSM으로 실행)
aws ssm send-command --instance-ids <worker-id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["nc -zvw 3 10.12.143.218 29092"]'

# Kafka 토픽 목록 확인 (브로커 EC2에서)
aws ssm send-command --instance-ids i-03b084858ace4138c \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo docker exec tasteam-kafka kafka-topics --list --bootstrap-server localhost:29092"]'

# 파드 내부에서 Kafka 연결 테스트
kubectl run nc-test --rm -it --image=busybox -n app-prod -- nc -zvw 5 10.12.143.218 29092

# Spring Boot 컨테이너 Kafka 로그 확인
kubectl logs -l app=spring-boot -n app-prod -c spring-boot --tail=200 | grep -iE "kafka|TimeoutException|disconnected|joined.group"

# Kafka advertised.listeners 확인
sudo docker exec tasteam-kafka cat /etc/kafka/kafka.properties | grep advertised
```

## 미해결 항목

- [x] ~~파드 → Kafka 브로커 연결 타임아웃~~: NetworkPolicy egress 허용 규칙 추가로 해결
- [ ] IMDS 접근: Linkerd 때문에 파드에서 EC2 메타데이터 서비스 접근 불가. IAM 정적 키로 우회 중
