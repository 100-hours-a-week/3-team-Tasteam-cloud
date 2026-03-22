# FI-04. AZ 2b 장애 시뮬레이션 런북

> AWS FIS 기반 멀티 AZ 내성 본시험

## 0. 문서 개요

| 항목 | 내용 |
|---|---|
| 실험 목적 | AZ 2b 전체 손실(cp-2b + worker-2b) 시에도 서비스가 유지되는지 검증 |
| 전제 조건 | **Track B 배포 완료** — cp 3대(2a/2b/2c) + worker 4대(2a-1/2a-2/2b/2c) |
| 장애 주입 수단 | AWS FIS (`aws:ec2:stop-instances`) |
| 관측 수단 | kubectl watch, NLB target health, curl health check loop |
| 실행 환경 | **kubectl**: `prod-ec2-k8s-cp-2a` (SSM) / **AWS CLI**: 로컬 (`--profile tasteam-v2`) |
| 부하 테스트 | 수행하지 않음 |
| 근거 문서 | `k8s_aws_fault_injection_scenarios_final.md` FI-04 |
| 작성 기준일 | 2026-03-22 |

### 가설

> AZ 2b가 손실되어도 etcd quorum(2/3)이 유지되고, 남은 worker 3대로 서비스가 지속되며, NLB가 unhealthy target을 자동 회피한다.

### 주요 변수 참조표

| 변수 | 값 | 비고 |
|---|---|---|
| `CP_2B_INSTANCE_ID` | `i-0b588f59170098bb7` | `prod-ec2-k8s-cp-2b` |
| `WORKER_2B_INSTANCE_ID` | `i-0dbf023b2340a5d96` | Track A부터 존재 |
| `API_TG_ARN` | `arn:aws:elasticloadbalancing:ap-northeast-2:203802643061:targetgroup/prod-k8s-apiserver-tg/f8162c9908829536` | kube-apiserver 6443 |
| `HTTP_TG_ARN` | `arn:aws:elasticloadbalancing:ap-northeast-2:203802643061:targetgroup/prod-k8s-ingress-http-tg/1a14d3aa2afcc1e7` | ingress 30080 |
| `HTTPS_TG_ARN` | `arn:aws:elasticloadbalancing:ap-northeast-2:203802643061:targetgroup/prod-k8s-ingress-https-tg/fe3518472b979a81` | ingress 30443 |
| `AWS_ACCOUNT_ID` | `203802643061` | |
| `AWS_REGION` | `ap-northeast-2` | |
| Private Subnet 2b | `subnet-0032f3bbf09324f9d` | 10.11.160.0/20 |

### AZ 2b stop 시 예상 영향

| 구성 요소 | 영향 |
|---|---|
| etcd | 3 → 2 member, quorum 유지 (read-write 정상) |
| kube-apiserver | cp-2b TG에서 빠짐, cp-2a + cp-2c가 처리 |
| worker | 4 → 3대, worker-2b의 Pod가 다른 노드로 재스케줄 |
| Ingress NLB | worker-2b unhealthy → 나머지 3대로 라우팅 |
| NAT Instance | 2a에 위치, 영향 없음 |

---

## Section A. Pre-flight

### Step A-1. 환경변수 세팅

- 실행 위치: **로컬** + `prod-ec2-k8s-cp-2a` (SSM) 양쪽 모두
- 목적: 이후 모든 Step에서 참조할 변수를 한 곳에서 정의
- 참고: `AWS_PROFILE=tasteam-v2` 설정으로 로컬 AWS CLI 명령은 자동으로 해당 프로필 사용
- 명령어:

```bash
# ── 인스턴스 ID ──
export CP_2B_INSTANCE_ID="i-0b588f59170098bb7"
export WORKER_2B_INSTANCE_ID="i-0dbf023b2340a5d96"

# ── NLB Target Group ARN ──
export API_TG_ARN="arn:aws:elasticloadbalancing:ap-northeast-2:203802643061:targetgroup/prod-k8s-apiserver-tg/f8162c9908829536"
export HTTP_TG_ARN="arn:aws:elasticloadbalancing:ap-northeast-2:203802643061:targetgroup/prod-k8s-ingress-http-tg/1a14d3aa2afcc1e7"
export HTTPS_TG_ARN="arn:aws:elasticloadbalancing:ap-northeast-2:203802643061:targetgroup/prod-k8s-ingress-https-tg/fe3518472b979a81"

# ── AWS ──
export AWS_REGION="ap-northeast-2"
export AWS_ACCOUNT_ID="203802643061"
export AWS_PROFILE="tasteam-v2"

# ── 검증 엔드포인트 ──
export HEALTH_URL="https://api.tasteam.kr/api/health"

# ── 로그 디렉토리 ──
export EXPERIMENT_TS=$(date +%Y%m%d-%H%M%S)
export LOG_DIR="/Users/kimsj/tmp/fi-04-${EXPERIMENT_TS}"
mkdir -p "${LOG_DIR}"
```

- 기대 결과:
  - `echo $CP_2B_INSTANCE_ID` 로 값 확인
  - `LOG_DIR` 디렉토리 생성됨
- 실패 징후:
  - 인스턴스 ID가 빈 문자열이면 이후 AWS CLI 실행 시 오류 발생

---

### Step A-2. 실험 전제 상태 확인

- 실행 위치: `prod-ec2-k8s-cp-2a` (SSM)
- 목적: Track B 7노드 전원 Ready, Pod 분포가 AZ 분산되어 있는지 확인
- 명령어:

```bash
# 노드 상태 — 7대 전원 Ready여야 함
kubectl get nodes -o wide

# Pod 분포 — app-prod 워크로드가 여러 AZ에 분산되어 있는지
kubectl get pods -n app-prod -o wide

# ingress-nginx replica 위치 확인
kubectl get pods -n ingress-nginx -o wide

# PDB 상태
kubectl get pdb -n app-prod
```

- 기대 결과:
  - cp-2a, cp-2b, cp-2c, worker-2a-1, worker-2a-2, worker-2b, worker-2c 모두 `Ready`
  - `spring-boot` 2개 replica 중 최소 1개는 worker-2b가 **아닌** 노드에 배치
  - `ingress-nginx` 2개 replica 모두 Ready
  - `spring-boot-pdb` — `ALLOWED DISRUPTIONS >= 1`
- 실패 징후:
  - 노드 7대 미만 → Track B 미배포 → **실험 중단**
  - spring-boot 2개가 모두 worker-2b에 배치 → `kubectl delete pod` 로 1개 재스케줄 유도 후 재확인
- 롤백 / 정리:
  - 전제 미충족 시 실험 진행하지 않음

---

### Step A-3. NLB TG health 기준치 확인

- 실행 위치: **로컬** (`AWS_PROFILE=tasteam-v2`)
- 목적: 3개 TG 모두 전원 healthy인 Before 상태 기록
- 명령어:

```bash
for TG_ARN in "${API_TG_ARN}" "${HTTP_TG_ARN}" "${HTTPS_TG_ARN}"; do
  TG_NAME=$(echo "${TG_ARN}" | sed 's|.*targetgroup/||' | sed 's|/.*||')
  echo "=== ${TG_NAME} ==="
  aws elbv2 describe-target-health \
    --target-group-arn "${TG_ARN}" \
    --profile tasteam-v2 \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State}' \
    --output table
done 2>&1 | tee "${LOG_DIR}/pre-tg-health.txt"
```

- 기대 결과:
  - API TG: cp 3대 모두 `healthy`
  - HTTP/HTTPS TG: worker 4대 모두 `healthy`
- 실패 징후:
  - 실험 전 unhealthy target 존재 → 원인 해소 후 재확인

---

### Step A-4. 실험 전 etcd 스냅샷

- 실행 위치: `prod-ec2-k8s-cp-2a` (SSM)
- 목적: 실험 전 etcd 상태 보존 (최악의 경우 복구 기준점)
- 명령어:

```bash
# etcd pod 이름 확인
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd \
  --field-selector spec.nodeName=prod-ec2-k8s-cp-2a -o jsonpath='{.items[0].metadata.name}')
echo "etcd pod: ${ETCD_POD}"

# 스냅샷 저장 (etcd pod 내부에서 실행)
kubectl exec -n kube-system "${ETCD_POD}" -- \
  etcdctl snapshot save /var/lib/etcd/etcd-fi04-pre.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 스냅샷 파일 확인 (etcd 3.6 distroless — 호스트에서 직접 확인)
ls -lh /var/lib/etcd/etcd-fi04-pre.db
```

- 기대 결과:
  - 스냅샷 파일이 존재하고 용량이 0보다 큼
- 실패 징후:
  - `context deadline exceeded` → etcd 미응답 → **실험 중단**

---

## Section B. FIS 실험 준비 (1회성 — 재실행 시 생략)

### Step B-1. FIS IAM Role 생성

- 실행 위치: **로컬** (`AWS_PROFILE=tasteam-v2`)
- 목적: AWS FIS가 EC2 인스턴스를 stop할 수 있는 최소 권한 Role 생성
- 명령어:

```bash
# 1) Role 생성 (FIS trust policy)
aws iam create-role \
  --role-name prod-fis-experiment-role \
  --profile tasteam-v2 \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{
      "Effect":"Allow",
      "Principal":{"Service":"fis.amazonaws.com"},
      "Action":"sts:AssumeRole"
    }]
  }'

# 2) 권한 정책 연결
aws iam put-role-policy \
  --role-name prod-fis-experiment-role \
  --policy-name fis-ec2-stop-policy \
  --profile tasteam-v2 \
  --policy-document '{
    "Version":"2012-10-17",
    "Statement":[
      {
        "Sid":"EC2Control",
        "Effect":"Allow",
        "Action":[
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ],
        "Resource":"*",
        "Condition":{
          "StringEquals":{
            "aws:ResourceTag/Project":"tasteam"
          }
        }
      },
      {
        "Sid":"CloudWatchStopCondition",
        "Effect":"Allow",
        "Action":["cloudwatch:DescribeAlarms"],
        "Resource":"*"
      },
      {
        "Sid":"FISLogging",
        "Effect":"Allow",
        "Action":[
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource":"arn:aws:logs:ap-northeast-2:203802643061:log-group:/aws/fis/*"
      }
    ]
  }'

export FIS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/prod-fis-experiment-role"
```

- 기대 결과:
  - Role ARN 반환됨
- 실패 징후:
  - `AccessDenied` → 실행 계정에 IAM 권한 부족
  - `EntityAlreadyExists` → 이미 생성됨, 정책만 확인
- 롤백 / 정리:
  - `aws iam delete-role-policy --role-name prod-fis-experiment-role --policy-name fis-ec2-stop-policy --profile tasteam-v2`
  - `aws iam delete-role --role-name prod-fis-experiment-role --profile tasteam-v2`

---

### Step B-2. Stop Condition CloudWatch Alarm 생성

- 실행 위치: **로컬** (`AWS_PROFILE=tasteam-v2`)
- 목적: API TG unhealthy 수가 3 이상이면 FIS가 자동 중단 (etcd quorum 붕괴 방지)
- 명령어:

```bash
# CloudWatch Logs Group 생성 (FIS 로그용)
aws logs create-log-group \
  --log-group-name /aws/fis/fi04 \
  --profile tasteam-v2 \
  --region ${AWS_REGION} 2>/dev/null || true

# Stop Condition Alarm
# NLB는 NetworkELB 네임스페이스 사용
aws cloudwatch put-metric-alarm \
  --alarm-name "fi04-stop-apiserver-tg-unhealthy" \                   # 알람 이름 (FIS stop condition ARN에서 참조)
  --alarm-description "FI-04 안전장치: API TG unhealthy >= 3이면 etcd quorum 위험" \
  --namespace "AWS/NetworkELB" \                                       # NLB 메트릭 네임스페이스
  --metric-name "UnHealthyHostCount" \                                 # health check 실패 타겟 수
  --profile tasteam-v2 \
  --dimensions \                                                       # 모니터링 대상 NLB + TG 지정
    Name=TargetGroup,Value="targetgroup/prod-k8s-apiserver-tg/f8162c9908829536" \
    Name=LoadBalancer,Value="net/prod-nlb-k8s-apiserver-int/31a8dd665634fec3" \
  --statistic Average \                                                # 집계: 평균
  --period 10 \                                                        # 수집 주기 10초 (최소값, 빠른 감지)
  --threshold 3 \                                                      # unhealthy >= 3이면 ALARM
  --comparison-operator GreaterThanOrEqualToThreshold \                # threshold 이상 시 발동
  --evaluation-periods 1 \                                             # 1회 평가로 즉시 발동
  --treat-missing-data notBreaching \                                  # 데이터 없으면 정상 간주 (오탐 방지)
  --region ${AWS_REGION}
```

- 기대 결과:
  - Alarm 상태 `OK`
- 실패 징후:
  - NLB/TG dimension 값이 잘못되면 `INSUFFICIENT_DATA` 상태 → dimension 재확인
- 롤백 / 정리:
  - `aws cloudwatch delete-alarms --alarm-names fi04-stop-apiserver-tg-unhealthy --profile tasteam-v2`

> **설계 근거**: cp 3대 중 1대(2b)만 stop하므로 unhealthy는 1이 정상. unhealthy >= 3이면 의도하지 않은 추가 장애 → 즉시 중단.

---

### Step B-3. FIS 실험 템플릿 등록

- 실행 위치: **로컬** (`AWS_PROFILE=tasteam-v2`)
- 목적: cp-2b + worker-2b 동시 stop 실험을 FIS 템플릿으로 등록
- 명령어:

```bash
cat > /Users/kimsj/tmp/fi04-template.json << 'TEMPLATE'
{
  "description": "FI-04: AZ 2b 장애 시뮬레이션 — cp-2b + worker-2b stop",
  "targets": {
    "AZ2bInstances": {
      "resourceType": "aws:ec2:instance",
      "resourceArns": [
        "arn:aws:ec2:ap-northeast-2:203802643061:instance/${CP_2B_INSTANCE_ID}",
        "arn:aws:ec2:ap-northeast-2:203802643061:instance/${WORKER_2B_INSTANCE_ID}"
      ],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "StopAZ2b": {
      "actionId": "aws:ec2:stop-instances",
      "parameters": {},
      "targets": {
        "Instances": "AZ2bInstances"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:ap-northeast-2:203802643061:alarm:fi04-stop-apiserver-tg-unhealthy"
    }
  ],
  "roleArn": "${FIS_ROLE_ARN}",
  "tags": {
    "Project": "tasteam",
    "Experiment": "FI-04"
  },
  "logConfiguration": {
    "logSchemaVersion": 2,
    "cloudWatchLogsConfiguration": {
      "logGroupArn": "arn:aws:logs:ap-northeast-2:203802643061:log-group:/aws/fis/fi04:*"
    }
  }
}
TEMPLATE

# 환경변수를 실제 값으로 치환 (macOS 기준, Linux는 sed -i 's/...' 사용)
sed -i '' \
  -e "s/\${CP_2B_INSTANCE_ID}/${CP_2B_INSTANCE_ID}/g" \
  -e "s/\${WORKER_2B_INSTANCE_ID}/${WORKER_2B_INSTANCE_ID}/g" \
  -e "s|\${FIS_ROLE_ARN}|${FIS_ROLE_ARN}|g" \
  /Users/kimsj/tmp/fi04-template.json

# 템플릿 등록
aws fis create-experiment-template \
  --cli-input-json file:///Users/kimsj/tmp/fi04-template.json \
  --profile tasteam-v2 \
  --region ${AWS_REGION} \
  --query 'experimentTemplate.id' \
  --output text | tee "${LOG_DIR}/fis-template-id.txt"

export FIS_TEMPLATE_ID=$(cat "${LOG_DIR}/fis-template-id.txt")
echo "FIS Template ID: ${FIS_TEMPLATE_ID}"
```

- 기대 결과:
  - Template ID 반환
- 실패 징후:
  - `ValidationException` → JSON 구조 오류 → `cat /Users/kimsj/tmp/fi04-template.json | jq .` 로 포맷 확인
  - `AccessDeniedException` → FIS Role 권한 확인
- 롤백 / 정리:
  - `aws fis delete-experiment-template --id ${FIS_TEMPLATE_ID} --profile tasteam-v2`

---

## Section C. Baseline 캡처

### Step C-1. 노드 / Pod 분포 스냅샷

- 실행 위치: `prod-ec2-k8s-cp-2a` (SSM)
- 목적: 장애 주입 전 기준 상태를 타임스탬프와 함께 저장 (Before 증적)
- 명령어:

```bash
TS=$(date +%Y%m%d-%H%M%S)

kubectl get nodes -o wide \
  | tee "${LOG_DIR}/baseline-nodes-${TS}.txt"

kubectl get pods -n app-prod -o wide \
  | tee "${LOG_DIR}/baseline-app-pods-${TS}.txt"

kubectl get pods -n ingress-nginx -o wide \
  | tee "${LOG_DIR}/baseline-ingress-pods-${TS}.txt"

kubectl get hpa -n app-prod \
  | tee "${LOG_DIR}/baseline-hpa-${TS}.txt"
```

- 기대 결과:
  - 4개 파일 생성, 각각 정상 상태 캡처됨
- 실패 징후:
  - kubectl timeout → etcd / API server 문제 → Step A-4 결과 재확인, 실험 중단 고려
  - LOG_DIR 없음 → Step A-1 재실행

---

### Step C-2. NLB TG health 스냅샷

- 실행 위치: **로컬** (`AWS_PROFILE=tasteam-v2`)
- 목적: 3개 TG의 Before healthy count 기록
- 명령어:

```bash
TS=$(date +%Y%m%d-%H%M%S)

for TG_ARN in "${API_TG_ARN}" "${HTTP_TG_ARN}" "${HTTPS_TG_ARN}"; do
  TG_NAME=$(echo "${TG_ARN}" | sed 's|.*targetgroup/||' | sed 's|/.*||')
  aws elbv2 describe-target-health \
    --target-group-arn "${TG_ARN}" \
    --profile tasteam-v2 \
    --output json
done | tee "${LOG_DIR}/baseline-tg-${TS}.json"
```

- 기대 결과:
  - API TG: 3/3 healthy
  - HTTP TG: 4/4 healthy
  - HTTPS TG: 4/4 healthy
- 실패 징후:
  - AWS CLI 오류 → AWS_REGION, 자격증명 확인
  - 실험 전 unhealthy target 존재 → Step A-3에 준하여 원인 해소

---

### Step C-3. Health check loop 시작

- 실행 위치: `prod-ec2-k8s-cp-2a` (SSM) — **별도 SSM 세션**
- 목적: 실험 전~중~후 서비스 가용성을 1초 단위로 기록 (부하 없이 단순 health check)
- 명령어:

```bash
# ── 별도 SSM 세션에서 실행 ──
# Step A-1 세션에서 echo $LOG_DIR 로 확인한 경로를 붙여넣기
# 또는 자동 탐색:
export LOG_DIR=$(ls -dt /Users/kimsj/tmp/fi-04-* 2>/dev/null | head -1)

echo "timestamp,endpoint,http_code,time_total" > "${LOG_DIR}/health-loop.csv"

while true; do
  TS=$(date +%Y%m%d-%H%M%S)
  RESULT=$(curl -s -o /dev/null \
    -w "%{http_code},%{time_total}" \
    --connect-timeout 5 --max-time 10 \
    "https://api.tasteam.kr/api/health" 2>/dev/null || echo "000,0")
  echo "${TS},api,${RESULT}" >> "${LOG_DIR}/health-loop.csv"
  sleep 1
done
```

- 기대 결과:
  - CSV에 1초마다 `타임스탬프,api,200,0.xxx` 행이 추가됨
- 실패 징후:
  - 실험 전부터 200이 아닌 응답 → 서비스 상태 확인 필요

---

### Step C-4. etcd member 상태 기록

- 실행 위치: `prod-ec2-k8s-cp-2a` (SSM)
- 목적: 3-member quorum 정상 상태 Before 기록
- 명령어:

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd \
  --field-selector spec.nodeName=prod-ec2-k8s-cp-2a -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n kube-system "${ETCD_POD}" -- \
  etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --write-out=table
```

- 기대 결과:
  - 3개 member 모두 `started` 상태
- 실패 징후:
  - member 수가 3 미만 → etcd 구성 문제 → **실험 중단**

---

## Section D. 장애 주입

### Step D-1. FIS 실험 시작

- 실행 위치: **로컬** (`AWS_PROFILE=tasteam-v2`)
- 목적: FIS로 cp-2b + worker-2b를 동시에 stop
- 명령어:

```bash
echo "[$(date +%Y%m%d-%H%M%S)] FI-04 장애 주입 시작" | tee "${LOG_DIR}/timeline.txt"

aws fis start-experiment \
  --experiment-template-id "${FIS_TEMPLATE_ID}" \
  --profile tasteam-v2 \
  --region ${AWS_REGION} \
  --query 'experiment.id' \
  --output text | tee "${LOG_DIR}/fis-experiment-id.txt"

export FIS_EXPERIMENT_ID=$(cat "${LOG_DIR}/fis-experiment-id.txt")
echo "Experiment ID: ${FIS_EXPERIMENT_ID}"
```

- 기대 결과:
  - Experiment ID 반환 (EXP 접두사)
- 실패 징후:
  - `ConflictException` → 동일 템플릿의 이전 실험이 아직 running → 완료 대기 후 재시도

---

### Step D-2. FIS 실험 상태 확인

- 실행 위치: **로컬** (`AWS_PROFILE=tasteam-v2`)
- 목적: FIS가 인스턴스를 실제로 stop했는지, stop condition이 발동하지 않았는지 확인
- 명령어:

```bash
# 10초 간격 폴링, 완료/중단/실패 시 자동 종료
for i in $(seq 1 12); do
  STATUS=$(aws fis get-experiment \
    --id "${FIS_EXPERIMENT_ID}" \
    --profile tasteam-v2 \
    --region ${AWS_REGION} \
    --query 'experiment.state.status' --output text)
  echo "--- poll ${i} ($(date +%H:%M:%S)) status: ${STATUS} ---"
  [[ "${STATUS}" == "completed" || "${STATUS}" == "stopped" || "${STATUS}" == "failed" ]] && break
  sleep 10
done
```

- 기대 결과:
  - 루프가 `completed`에서 자동 종료
  - `stopped`나 `failed`가 아닌 `completed`여야 정상
- 실패 징후:
  - `status: stopped` + reason에 alarm ARN → stop condition 발동 → **Section F로 즉시 이동**
  - `status: failed` → FIS 로그 확인: `aws logs tail /aws/fis/fi04 --profile tasteam-v2`

---

### Step D-3. 노드 NotReady 전환 확인

- 실행 위치: **로컬** (AWS CLI) + `prod-ec2-k8s-cp-2a` (SSM, kubectl)
- 목적: cp-2b, worker-2b가 `NotReady`로 전환되는 시각 기록
- 명령어:

```bash
# 별도 SSM 세션에서 watch (Ctrl+C로 중단)
kubectl get nodes -w &

# 현재 상태 확인
kubectl get nodes | grep -E "cp-2b|worker-2b"

# EC2 상태 직접 확인
aws ec2 describe-instance-status \
  --instance-ids "${CP_2B_INSTANCE_ID}" "${WORKER_2B_INSTANCE_ID}" \
  --include-all-instances \
  --profile tasteam-v2 \
  --query 'InstanceStatuses[*].{ID:InstanceId,State:InstanceState.Name}' \
  --output table

# 타임라인 기록
echo "[$(date +%Y%m%d-%H%M%S)] 노드 NotReady 전환 확인" | tee -a "${LOG_DIR}/timeline.txt"
```

- 기대 결과:
  - kubelet 통신 끊김 후 약 40초 내 `NotReady` 전환 (node-monitor-grace-period 기본값 40s)
  - EC2 상태: `stopped`
- 실패 징후:
  - 5분 이상 `Ready` 유지 → FIS action이 실행되지 않음 → `aws fis get-experiment --profile tasteam-v2` 로 상태 재확인

---

## Section E. 장애 중 관측

### Step E-1. etcd quorum / API endpoint 생존 확인

- 실행 위치: `prod-ec2-k8s-cp-2a` (SSM)
- 목적: cp-2b 손실 후 etcd 2/3 quorum 유지, kubectl 정상 응답 검증
- 명령어:

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd \
  --field-selector spec.nodeName=prod-ec2-k8s-cp-2a -o jsonpath='{.items[0].metadata.name}')

# etcd member 상태
kubectl exec -n kube-system "${ETCD_POD}" -- \
  etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --write-out=table

# etcd endpoint health
kubectl exec -n kube-system "${ETCD_POD}" -- \
  etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# kubectl 동작 확인
kubectl get nodes
kubectl cluster-info
kubectl get pods -n app-prod
```

- 기대 결과:
  - etcd: 2개 member `started`, cp-2b member는 응답 없음
  - `kubectl` 명령어 모두 정상 응답
  - cp-2b는 `NotReady`로 표시되지만 API는 지속
- 실패 징후:
  - `kubectl` timeout → etcd quorum 손실 가능성 → **Section F로 즉시 이동**

```bash
# 타임라인 기록
echo "[$(date +%Y%m%d-%H%M%S)] etcd quorum 확인 — 2/3 유지" | tee -a "${LOG_DIR}/timeline.txt"
```

---

### Step E-2. NLB TG health 변화 관측

- 실행 위치: **로컬** (`AWS_PROFILE=tasteam-v2`)
- 목적: 3개 TG의 unhealthy 전환 시각과 healthy count 기록
- 명령어:

```bash
TS=$(date +%Y%m%d-%H%M%S)

for TG_ARN in "${API_TG_ARN}" "${HTTP_TG_ARN}" "${HTTPS_TG_ARN}"; do
  TG_NAME=$(echo "${TG_ARN}" | sed 's|.*targetgroup/||' | sed 's|/.*||')
  echo "=== ${TG_NAME} ==="
  aws elbv2 describe-target-health \
    --target-group-arn "${TG_ARN}" \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
    --output table
done 2>&1 | tee "${LOG_DIR}/during-tg-health-${TS}.txt"

echo "[$(date +%Y%m%d-%H%M%S)] NLB TG unhealthy 전환 확인" | tee -a "${LOG_DIR}/timeline.txt"
```

- 기대 결과:
  - API TG: cp-2b 1개 `unhealthy`, 나머지 2개 `healthy`
  - HTTP/HTTPS TG: worker-2b 1개 `unhealthy`, 나머지 3개 `healthy`
  - health check interval 10s × unhealthy threshold 2 = 약 **20초** 내 전환
- 실패 징후:
  - unhealthy 2개 이상 → 의도치 않은 추가 장애 → 상황 판단 후 Section F 고려

---

### Step E-3. Pod 재스케줄 관측

- 실행 위치: `prod-ec2-k8s-cp-2a` (SSM)
- 목적: worker-2b에 있던 Pod가 생존 worker로 재스케줄되는 시간 측정
- 명령어:

```bash
echo "[$(date +%Y%m%d-%H%M%S)] Pod 재스케줄 관측 시작" | tee -a "${LOG_DIR}/timeline.txt"

# 10초마다 Pod 상태 캡처 (2분간)
for i in $(seq 1 12); do
  TS=$(date +%Y%m%d-%H%M%S)
  echo "--- ${TS} ---"
  kubectl get pods -n app-prod -o wide
  echo ""
  sleep 10
done 2>&1 | tee "${LOG_DIR}/pod-reschedule.txt"

echo "[$(date +%Y%m%d-%H%M%S)] Pod 재스케줄 관측 종료" | tee -a "${LOG_DIR}/timeline.txt"
```

- 기대 결과:
  - worker-2b Pod: `Terminating` → 다른 노드에서 새 Pod `Pending` → `Running`
  - `spring-boot`: PDB minAvailable=1 보장, 항상 최소 1개 Running
  - `fastapi`: PDB 없으므로 일시적 0/1 가능 (단일 replica)
  - 재스케줄 완료까지 약 1~5분 (pod-eviction-timeout, image pull 시간 포함)
- 실패 징후:
  - 5분 초과 `Pending` → 남은 worker capacity 부족 → `kubectl describe pod` 로 원인 확인

---

### Step E-4. Health check loop 중간 결과 확인

- 실행 위치: `prod-ec2-k8s-cp-2a` (SSM)
- 목적: 장애 주입 후 서비스 가용성 중간 점검
- 명령어:

```bash
# 성공/실패 집계
echo "=== 현재까지 집계 ==="
awk -F',' 'NR>1 {print $3}' "${LOG_DIR}/health-loop.csv" | sort | uniq -c | sort -rn

# 200이 아닌 응답만 추출
echo ""
echo "=== 비정상 응답 ==="
grep -v ",200," "${LOG_DIR}/health-loop.csv" | grep -v "^timestamp" | head -20

# 최근 10행
echo ""
echo "=== 최근 ==="
tail -10 "${LOG_DIR}/health-loop.csv"
```

- 기대 결과:
  - 대부분 200, 장애 직후 짧은 구간에 5xx 또는 timeout 발생 가능
  - NLB unhealthy 전환 후(~20초) 정상 복귀
- 실패 징후:
  - 지속적 5xx → NLB가 unhealthy target을 회피하지 못하고 있음 → TG 설정 확인

---

### Step E-5. 배포 / HPA 동작 확인 (선택)

- 실행 위치: `prod-ec2-k8s-cp-2a` (SSM)
- 목적: AZ 2b 손실 상태에서도 control-plane 기능이 정상인지 추가 검증
- 명령어:

```bash
# HPA 상태 조회
kubectl get hpa -n app-prod

# Deployment rollout 상태
kubectl rollout status deployment/spring-boot -n app-prod --timeout=30s

# (선택) dummy annotation으로 롤링 업데이트 트리거
# kubectl annotate deployment spring-boot -n app-prod \
#   fi04-test="$(date +%s)" --overwrite
```

- 기대 결과:
  - HPA 조회 정상 응답
  - rollout status 정상
- 실패 징후:
  - API timeout → etcd quorum 문제 → Step E-1 재확인

---

## Section F. 복구

### Step F-1. FIS 실험 상태 최종 확인

- 실행 위치: **로컬** (`AWS_PROFILE=tasteam-v2`)
- 목적: FIS 실험 완료 여부 확인 후 복구 진행
- 명령어:

```bash
aws fis get-experiment \
  --id "${FIS_EXPERIMENT_ID}" \
  --profile tasteam-v2 \
  --region ${AWS_REGION} \
  --query '{Status:experiment.state.status,Reason:experiment.state.reason,Start:experiment.startTime,End:experiment.endTime}' \
  --output table
```

- 기대 결과:
  - `status: completed` — 정상 완료
- 실패 징후:
  - `status: running` → 아직 실행 중 → 완료 대기 또는 수동 중단: `aws fis stop-experiment --id ${FIS_EXPERIMENT_ID} --profile tasteam-v2`

---

### Step F-2. EC2 인스턴스 재시작

- 실행 위치: **로컬** (`AWS_PROFILE=tasteam-v2`)
- 목적: cp-2b + worker-2b 재시작 (kubeadm 노드는 kubelet 자동 재합류)
- 명령어:

```bash
echo "[$(date +%Y%m%d-%H%M%S)] 복구 시작 — EC2 start" | tee -a "${LOG_DIR}/timeline.txt"

aws ec2 start-instances \
  --instance-ids "${CP_2B_INSTANCE_ID}" "${WORKER_2B_INSTANCE_ID}" \
  --profile tasteam-v2 \
  --region ${AWS_REGION}

# running 상태 대기
aws ec2 wait instance-running \
  --instance-ids "${CP_2B_INSTANCE_ID}" "${WORKER_2B_INSTANCE_ID}" \
  --profile tasteam-v2 \
  --region ${AWS_REGION}

echo "[$(date +%Y%m%d-%H%M%S)] EC2 running 전환 완료" | tee -a "${LOG_DIR}/timeline.txt"
```

- 기대 결과:
  - 두 인스턴스 모두 `running`
- 실패 징후:
  - `wait` timeout → AWS Console에서 인스턴스 상태 직접 확인

---

### Step F-3. 노드 Ready 복귀 대기

- 실행 위치: `prod-ec2-k8s-cp-2a` (SSM)
- 목적: kubelet 자동 재합류로 노드가 `Ready`로 돌아오는 시각 기록
- 명령어:

```bash
# cp-2b Ready 대기 (최대 10분)
kubectl wait --for=condition=Ready node/prod-ec2-k8s-cp-2b --timeout=600s
echo "[$(date +%Y%m%d-%H%M%S)] cp-2b Ready 복귀" | tee -a "${LOG_DIR}/timeline.txt"

# worker-2b Ready 대기
kubectl wait --for=condition=Ready node/prod-ec2-k8s-worker-2b --timeout=600s
echo "[$(date +%Y%m%d-%H%M%S)] worker-2b Ready 복귀" | tee -a "${LOG_DIR}/timeline.txt"

# 전체 노드 상태 확인
kubectl get nodes -o wide | tee "${LOG_DIR}/recovery-nodes.txt"
```

- 기대 결과:
  - EC2 start 후 약 2~5분 내 `Ready` 복귀
  - 7노드 전원 `Ready`
- 실패 징후:
  - 10분 초과 `NotReady` → SSM으로 접속하여 kubelet 상태 확인:
    ```bash
    sudo systemctl status kubelet
    sudo journalctl -u kubelet --since "10 min ago" | tail -50
    ```
- 롤백 / 정리:
  - kubelet 문제 시: `sudo systemctl restart kubelet`

---

### Step F-4. NLB TG 전원 healthy 복귀 확인

- 실행 위치: **로컬** (`AWS_PROFILE=tasteam-v2`)
- 목적: 3개 TG 모두 Before 상태(전원 healthy)로 복귀했는지 확인
- 명령어:

```bash
TS=$(date +%Y%m%d-%H%M%S)

for TG_ARN in "${API_TG_ARN}" "${HTTP_TG_ARN}" "${HTTPS_TG_ARN}"; do
  TG_NAME=$(echo "${TG_ARN}" | sed 's|.*targetgroup/||' | sed 's|/.*||')
  echo "=== ${TG_NAME} ==="
  aws elbv2 describe-target-health \
    --target-group-arn "${TG_ARN}" \
    --profile tasteam-v2 \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id,State:TargetHealth.State}' \
    --output table
done 2>&1 | tee "${LOG_DIR}/recovery-tg-health-${TS}.txt"

echo "[$(date +%Y%m%d-%H%M%S)] NLB TG 전원 healthy 복귀" | tee -a "${LOG_DIR}/timeline.txt"
```

- 기대 결과:
  - API TG: 3/3 healthy
  - HTTP/HTTPS TG: 4/4 healthy
- 실패 징후:
  - 노드 Ready인데 TG unhealthy → health check port(6443/30080/30443) 서비스 미기동 → 해당 노드에서 서비스 확인

---

### Step F-5. Health check loop 종료 / 결과 저장

- 실행 위치: `prod-ec2-k8s-cp-2a` (SSM)
- 목적: health check loop를 종료하고 전체 가용성 결과 집계
- 명령어:

```bash
# 별도 SSM 세션의 loop를 Ctrl+C로 종료

# 최종 집계
echo "=== FI-04 Health Check 최종 결과 ===" | tee "${LOG_DIR}/health-summary.txt"

TOTAL=$(awk -F',' 'NR>1' "${LOG_DIR}/health-loop.csv" | wc -l | tr -d ' ')
SUCCESS=$(grep -c ",200," "${LOG_DIR}/health-loop.csv" || echo 0)
FAIL=$((TOTAL - SUCCESS))
RATE=$(echo "scale=2; ${SUCCESS} * 100 / ${TOTAL}" | bc)

echo "총 요청: ${TOTAL}" | tee -a "${LOG_DIR}/health-summary.txt"
echo "성공(200): ${SUCCESS}" | tee -a "${LOG_DIR}/health-summary.txt"
echo "실패: ${FAIL}" | tee -a "${LOG_DIR}/health-summary.txt"
echo "가용성: ${RATE}%" | tee -a "${LOG_DIR}/health-summary.txt"

echo "" | tee -a "${LOG_DIR}/health-summary.txt"
echo "=== 비정상 응답 상세 ===" | tee -a "${LOG_DIR}/health-summary.txt"
grep -v ",200," "${LOG_DIR}/health-loop.csv" | grep -v "^timestamp" \
  | tee -a "${LOG_DIR}/health-summary.txt"

echo "" | tee -a "${LOG_DIR}/health-summary.txt"
echo "[$(date +%Y%m%d-%H%M%S)] FI-04 실험 완료" | tee -a "${LOG_DIR}/timeline.txt"

# 타임라인 최종 출력
echo ""
echo "=== 전체 타임라인 ==="
cat "${LOG_DIR}/timeline.txt"
```

- 기대 결과:
  - 가용성 95% 이상 (Pass 기준)
  - 비정상 응답은 장애 주입 직후 짧은 구간에 집중
- 실패 징후:
  - `health-loop.csv` 없음 → C-3의 별도 SSM 세션 `LOG_DIR` 경로 불일치 확인
  - 가용성 < 95% → Section G-4 판정 기준 대조 후 Partial/Fail 기록

---

## Section G. 포트폴리오 증적 정리

### Step G-1. 타임라인 테이블

`timeline.txt` 기반으로 아래 테이블을 완성한다.

| 이벤트 | 시각 | T+경과(초) | 비고 |
|---|---|---|---|
| FIS 실험 시작 | | T+0 | `start-experiment` |
| cp-2b EC2 stopped | | T+? | `describe-instance-status` |
| worker-2b EC2 stopped | | T+? | 동시 stop |
| cp-2b NotReady | | T+? | kubelet timeout ~40s |
| worker-2b NotReady | | T+? | |
| API TG: cp-2b unhealthy | | T+? | interval 10s × threshold 2 = ~20s |
| Ingress TG: worker-2b unhealthy | | T+? | |
| worker-2b Pod Terminating | | T+? | |
| 새 Pod Running (다른 노드) | | T+? | |
| EC2 start 명령 | | T+? | |
| cp-2b Ready 복귀 | | T+? | kubelet 자동 재합류 |
| worker-2b Ready 복귀 | | T+? | |
| TG 전원 healthy | | T+? | 실험 완전 종료 |

### Step G-2. Before/After 비교표

| 관측 항목 | Before | During (장애 중) | After (복구 후) |
|---|---|---|---|
| Ready 노드 수 | 7/7 | 5/7 | 7/7 |
| API TG healthy | 3/3 | 2/3 | 3/3 |
| Ingress TG healthy | 4/4 | 3/4 | 4/4 |
| spring-boot Running | 2/2 | ?/2 (재스케줄 중) | 2/2 |
| fastapi Running | 1/1 | ?/1 | 1/1 |
| Health check 가용성 | 100% | ?% | 100% |
| etcd member | 3 started | 2 started + 1 unreachable | 3 started |

### Step G-3. 아키텍처 근거 서술

포트폴리오에 쓸 때 아래 5가지를 **설계 결정 → 실험 결과**로 연결하여 서술한다.

**1) etcd quorum 2/3 유지**
> cp 3대를 각 AZ에 1대씩 분산 배치하여 AZ 1개 손실 시에도 etcd 과반수(2/3)를 확보.
> 실험 결과: cp-2b stop 후 kubectl / HPA / rollout 모두 정상 동작 확인.

**2) NLB health check 파라미터**
> API TG의 health check를 interval 10s + unhealthy threshold 2로 설정하여 최대 20초 내 unhealthy 전환.
> 실험 결과: T+?초에 unhealthy 전환, NLB가 즉시 healthy target으로만 라우팅.

**3) PDB minAvailable=1**
> spring-boot에 PDB minAvailable=1을 설정하여 장애 시에도 최소 1개 replica를 보장.
> 실험 결과: worker-2b 손실 시에도 다른 노드의 replica가 Running 유지.

**4) Worker N+1 설계**
> worker 4대 중 2a에 2대를 배치하여 AZ 2b 손실 시 남은 3대(2a-1, 2a-2, 2c)로 전체 워크로드 수용 가능.
> 실험 결과: 재스케줄 완료 후 모든 Pod Running, resource 여유 확인.

**5) AWS FIS를 통한 카오스 엔지니어링**
> 단순 `ec2 stop`이 아닌 AWS FIS를 활용하여 실험 ID, CloudWatch stop condition, 자동 로깅 체계를 갖춤.
> 프로덕션에서 안전하게 반복 가능한 장애 훈련 워크플로를 구축.

### Step G-4. 판정 기준

| 항목 | Pass | Partial | Fail |
|---|---|---|---|
| etcd quorum | kubectl 정상 응답 유지 | 일시적 지연 후 복구 | kubectl timeout |
| API endpoint | API TG unhealthy 1개만 | — | unhealthy 2개 이상 |
| 서비스 가용성 | 5xx < 1%, 복구 < 60초 | 5xx < 5%, 복구 < 3분 | 5xx > 5% 또는 복구 3분 초과 |
| Pod 재스케줄 | 5분 내 전체 Running | 10분 내 Running | 10분 초과 또는 Pending 지속 |
| 자동 복귀 | EC2 start 후 수동 개입 없이 Ready + healthy | — | kubelet 수동 재시작 필요 |

**최종 판정**: \_\_\_\_\_\_ (Pass / Partial / Fail)

---

## 실험 후 정리

```bash
# FIS 리소스 정리 (선택)
aws fis delete-experiment-template --id ${FIS_TEMPLATE_ID} --profile tasteam-v2
aws cloudwatch delete-alarms --alarm-names fi04-stop-apiserver-tg-unhealthy --profile tasteam-v2
aws logs delete-log-group --log-group-name /aws/fis/fi04 --profile tasteam-v2
# IAM Role은 재실험 가능성이 있으면 유지

# 로그 아카이브
tar -czf fi-04-${EXPERIMENT_TS}.tar.gz -C /tmp "fi-04-${EXPERIMENT_TS}"
echo "증적 아카이브: fi-04-${EXPERIMENT_TS}.tar.gz"
```
