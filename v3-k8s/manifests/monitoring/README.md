# 카오스 관측용 최소 모니터링 설치

> 목적: 카오스 엔지니어링(FI-06~09) 실험의 서버사이드 메트릭을 **기존 shared Prometheus(prom-dev)** 로 push
> 범위: **최소** — Alloy(수집) + kube-state-metrics(K8s 오브젝트). Linkerd viz / Spring Actuator는 후속
> 설계 근거: [../../docs/k8s-monitoring-integration.md](../../docs/k8s-monitoring-integration.md)

## 배포 방식 — ArgoCD GitOps

앱 계층과 동일하게 **ArgoCD GitOps**로 관리한다. 전용 AppProject `tasteam-monitoring` + Application 3개.

| ArgoCD 리소스 | sync-wave | 내용 |
|---|---|---|
| `argocd/projects/tasteam-monitoring-project.yaml` | — | 전용 AppProject |
| `argocd/apps/monitoring-resources.yaml` | 0 | 이 디렉토리의 plain manifest (ns / ExternalSecret / RBAC) |
| `argocd/apps/kube-state-metrics.yaml` | 1 | KSM helm (multi-source: chart + 이 repo values) |
| `argocd/apps/alloy.yaml` | 2 | Alloy helm (multi-source: chart + 이 repo values) |

## 구성 요소 (이 디렉토리 — monitoring-resources App이 동기화)

| 파일 | 역할 |
|---|---|
| `namespace.yaml` | `monitoring` ns |
| `external-secret.yaml` | prom-dev basic_auth 자격증명 (SSM → K8s Secret) |
| `alloy-cadvisor-rbac.yaml` | Alloy의 cadvisor scrape용 `nodes/proxy` 권한(보강) |
| `../helm/values/kube-state-metrics.yaml` | KSM helm values (kube-state-metrics App이 참조) |
| `../helm/values/alloy.yaml` | Alloy helm values (config 포함, remote_write push) |

## 수집 메트릭 → 카오스 매핑

| 메트릭 | 출처 | 시나리오 |
|---|---|---|
| `kube_horizontalpodautoscaler_status_current_replicas` | KSM | FI-08 HPA scale-out |
| `kube_deployment_status_replicas_available` | KSM | FI-06 가용 replica |
| `kube_pod_status_phase`, `..._restarts_total` | KSM | FI-06 재스케줄/재시작 |
| `kube_poddisruptionbudget_status_*` | KSM | FI-06 PDB |
| `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes` | cadvisor | FI-08 CPU/OOM |

---

## 설치 절차

### 0. 사전 — SSM 파라미터 등록 (최초 1회)

prom-dev basic_auth 자격증명을 SSM에 등록 (값은 k6 스크립트와 동일):

값은 k6 스크립트(`scripts/loadtest/run-fi-steady.sh`)의 `K6_PROMETHEUS_RW_USERNAME` / `_PASSWORD`와 동일하게 사용한다.

```bash
aws ssm put-parameter --profile tasteam-v2 --type SecureString \
  --name /prod/tasteam/monitoring/prom-rw-username --value '<run-fi-steady.sh의 USERNAME>'
aws ssm put-parameter --profile tasteam-v2 --type SecureString \
  --name /prod/tasteam/monitoring/prom-rw-password --value '<run-fi-steady.sh의 PASSWORD>'
```

### 1. AppProject + Application 등록 (GitOps)

```bash
# 전용 프로젝트
kubectl apply -f argocd/projects/tasteam-monitoring-project.yaml
# Application 3개 (sync-wave 순서로 자동 동기화: resources → KSM → Alloy)
kubectl apply -f argocd/apps/monitoring-resources.yaml
kubectl apply -f argocd/apps/kube-state-metrics.yaml
kubectl apply -f argocd/apps/alloy.yaml
```

이후는 ArgoCD가 자동 동기화(automated + selfHeal). git에 push된 변경은 자동 반영된다.

```bash
# 동기화 상태 확인
argocd app list -l component=monitoring
# 또는
kubectl -n argocd get applications -l component=monitoring
```

> `alloy-cadvisor-rbac.yaml`은 `monitoring-resources` App에 포함되어 함께 동기화된다(수동 apply 불필요).
> chart 기본 RBAC이 이미 `nodes/proxy`를 포함하면 중복이지만 무해.

---

## 검증

```bash
# 1. Alloy DaemonSet 전 노드 Running
kubectl -n monitoring get ds,pod -l app.kubernetes.io/name=alloy

# 2. KSM 메트릭 노출 확인
kubectl -n monitoring port-forward svc/kube-state-metrics 8080:8080 &
curl -s localhost:8080/metrics | grep kube_horizontalpodautoscaler_status_current_replicas

# 3. Alloy → prom-dev push 도달 확인 (shared Prometheus에서)
#    PromQL: up{role="k8s"}  →  타겟이 1 이면 push 성공
#    PromQL: kube_horizontalpodautoscaler_status_current_replicas{namespace="app-prod"}

# 4. Grafana(grafana.tasteam.kr)에서 role=k8s 필터로 그래프 표출 확인
```

### 스모크 (카오스 연계)

FI-06 1회 주입 후 Grafana에서 `kube_pod_status_phase{namespace="app-prod"}` 시계열에 Pod 종료→재생성이 잡히면 관측 파이프라인 정상.

---

## 트러블슈팅

| 증상 | 원인 | 조치 |
|---|---|---|
| Alloy 로그 `401` | basic_auth 불일치 | SSM 값 / Secret 재확인 |
| `up{role="k8s"}` 없음 | egress(VPC Peering) 차단 | 보안그룹/NACL, prom-dev 도달성 확인 |
| cadvisor scrape `403` | `nodes/proxy` 권한 부족 | `alloy-cadvisor-rbac.yaml` 적용 |
| 메트릭 중복 | clustering 미동작 | `alloy.clustering.enabled` 및 scrape `clustering` 확인 |
