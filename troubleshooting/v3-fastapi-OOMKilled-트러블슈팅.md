# v3 FastAPI Pod OOMKilled 트러블슈팅

## 증상
- FastAPI Pod이 기동 중 반복적으로 OOMKilled
- limit 2Gi → OOMKilled, 3Gi → OOMKilled
- CrashLoopBackOff 반복

## 원인 분석

### 1차: 메모리 limit 부족
- FastAPI가 부팅 시 HuggingFace 임베딩 모델(`paraphrase-multilingual-mpnet-base-v2`) 다운로드 + ONNX 로드
- 로컬 Docker 측정 기준 피크 메모리 **~1.7Gi** (docker stats, RSS 기준)
- 클러스터(x86)에서는 anon-rss **~2.0Gi** (dmesg 커널 로그 확인)
- 아키텍처 차이(ARM vs x86)로 ~300Mi 차이 발생

### 2차: 노드 물리 메모리 부족 (global OOM)
- limit을 3Gi로 올려도 OOMKilled 지속
- `dmesg` 확인 결과 `constraint=CONSTRAINT_NONE, global_oom` → **노드 전체 메모리 고갈**
- worker-2b(t3.medium, 4Gi)에 spring-boot + argocd 4개 + fastapi가 몰려있었음
- app-dev 깨진 Pod들도 리소스 점유 중

### 3차: 롤링 업데이트 교착 상태
- `maxUnavailable: 0`으로 인해 구 Pod 삭제 대기 ↔ 신 Pod 리소스 부족 → 교착
- 수동으로 구 Pod 삭제 필요

## 해결

### 즉시 조치
1. app-dev 깨진 deployment 전부 삭제 → 리소스 확보
2. worker-2b cordon → fastapi Pod 삭제 → worker-2c로 재스케줄
3. 2c에서 2/2 Running 확인 후 uncordon

### 매니페스트 수정
- `resources.limits.memory`: 1Gi → 3Gi
- `resources.requests.memory`: 512Mi → 2Gi
- `startupProbe` 추가: 모델 다운로드 대기 (10s × 30회 = 최대 5분)

### 실측 메모리 (cgroup v2, worker-2c에서 정상 기동 후)
- `memory.current` (유휴): **1.75Gi** (1,883,365,376 bytes)
- `memory.peak` (부팅 피크): **2.07Gi** (2,227,757,056 bytes)
- `memory.max` (limit): **3Gi** (3,221,225,472 bytes)
- request를 2Gi로 설정 — 피크(2.07Gi)를 커버하여 스케줄러가 물리 메모리 부족 노드에 배치 방지

## cgroup 메모리 직접 확인 방법

```bash
# 현재 사용량 (RSS + 파일 캐시, k8s가 실제로 보는 값)
kubectl exec -n app-prod <pod명> -c fastapi -- cat /sys/fs/cgroup/memory.current

# 컨테이너 생성 이후 최대 사용량
kubectl exec -n app-prod <pod명> -c fastapi -- cat /sys/fs/cgroup/memory.peak

# limit
kubectl exec -n app-prod <pod명> -c fastapi -- cat /sys/fs/cgroup/memory.max
```

- `docker stats`는 RSS만 보여주지만 cgroup은 파일 캐시도 포함 → 클러스터에서는 cgroup 값이 정확
- `kubectl top`이 안 되는 노드에서도 이 방법으로 확인 가능

## 진단 명령어 모음

```bash
# 커널 OOM 로그 (워커 노드에서)
sudo dmesg | grep -i "oom\|killed" | tail -20

# 노드별 Pod 배치 확인
kubectl get pods -A -o wide --field-selector spec.nodeName=<노드명>

# Pod 리소스 실사용량
kubectl top pod -n app-prod

# 노드 리소스 상태
kubectl top nodes
kubectl describe nodes | grep -A5 "Allocated resources"

# Pod 내부 헬스체크
kubectl exec -n app-prod <pod명> -c fastapi -- curl -s http://localhost:8000/health

# 이전 크래시 로그
kubectl logs -n app-prod -l app=fastapi -c fastapi --tail=50 --previous
```

## 교훈
- `docker stats`(RSS)와 k8s cgroup 메모리 카운팅은 다름 — 파일 캐시 포함 여부
- x86 vs ARM 아키텍처 간 메모리 사용량 차이 존재
- t3.medium(4Gi)에서 ML 모델 로딩 워크로드는 노드 배치 전략이 중요
- `maxUnavailable: 0` + 리소스 부족 → 교착 상태 가능성 인지 필요
- global OOM vs cgroup OOM 구분은 `dmesg`로만 가능 (`kubectl describe`로는 구분 불가)