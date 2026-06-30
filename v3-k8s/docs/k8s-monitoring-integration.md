# K8s 클러스터 모니터링 통합 설계

> 작성 기준일: 2026-06-29
> 목적: v3 K8s 클러스터의 메트릭을 **기존 shared 모니터링 스택(Prometheus/Grafana/Loki)** 으로 통합
> 전략: 신규 모니터링 스택 구축이 아닌, **검증된 Alloy push 모델을 K8s로 확장**
> 관련: [chaos-mesh-l2-design.md](fault-injection/chaos-mesh/chaos-mesh-l2-design.md) — 카오스 실험의 관측 기반

---

## 목차

1. [배경 및 목적](#1-배경-및-목적)
2. [현재 구성 (코드베이스 기반 유추)](#2-현재-구성-코드베이스-기반-유추)
3. [문제 정의 — K8s 메트릭 수집 갭](#3-문제-정의--k8s-메트릭-수집-갭)
4. [설계 — Alloy DaemonSet + kube-state-metrics](#4-설계--alloy-daemonset--kube-state-metrics)
5. [수집 대상 메트릭](#5-수집-대상-메트릭)
6. [라벨링 컨벤션 (기존 계승 + K8s 확장)](#6-라벨링-컨벤션-기존-계승--k8s-확장)
7. [GitOps 통합 (ArgoCD)](#7-gitops-통합-argocd)
8. [검증 방법](#8-검증-방법)
9. [카오스 엔지니어링 연계](#9-카오스-엔지니어링-연계)
10. [리스크 및 오픈 이슈](#10-리스크-및-오픈-이슈)

---

## 1. 배경 및 목적

### 1-1. 배경

- v2(EC2/Docker) 시절 **shared 모니터링 EC2**(Prometheus + Grafana + Loki + Alloy)가 별도로 운영 중
- 각 EC2는 Grafana Alloy로 메트릭을 shared Prometheus에 **push(remote_write)** — VPC Peering 통신
- v3에서 워크로드가 K8s로 이전되었으나, **K8s 클러스터 메트릭을 수집하는 경로가 부재**

### 1-2. 목적

- K8s 클러스터의 노드/컨테이너/워크로드 메트릭을 **기존 shared 스택으로 통합** 수집
- 카오스 엔지니어링(FI-06~09) 실험의 정량 관측 기반 확보 — HPA replica, Pod 상태, CPU 등
- **신규 스택 구축 회피** — 기존 Grafana/Prometheus 재사용, 운영 일원화

### 1-3. 원칙

- 기존 push 아키텍처·라벨링 컨벤션을 **변경 없이 계승**, K8s 차원만 확장
- 클러스터 내부에 Prometheus/Grafana를 새로 세우지 않음(중복 회피)

---

## 2. 현재 구성 (코드베이스 기반 유추)

> 클러스터 직접 접근 없이 `v2-docker/monitoring/` 및 alloy 설정 파일로 유추한 결과.

### 2-1. Shared 모니터링 스택 (클러스터 밖 EC2)

`v2-docker/monitoring/docker-compose.yml` 기준 — 단일 EC2의 docker-compose 스택:

| 컴포넌트 | 버전 | 역할 |
|---|---|---|
| Prometheus | v3.3.0 | remote_write 수신 + Kafka JMX 직접 scrape |
| Grafana | 11.6.0 | 시각화 — `grafana.tasteam.kr` |
| Loki | 3.4.2 | 로그 수집 |
| Alloy | v1.14.0-rc.1 | 자체 노드 메트릭 수집 |

- Grafana datasource: **Prometheus / Loki / CloudWatch** 연결됨(`grafana/provisioning/datasources/datasources.yml`)
- Prometheus 수신 엔드포인트: `http://<PROMETHEUS_HOST>:9090/api/v1/write`

### 2-2. 메트릭 수집 모델 — Alloy push

- 각 EC2에 Alloy 배포 → `prometheus.exporter.unix`(node), `prometheus.exporter.cadvisor`(컨테이너), Spring Actuator scrape
- 수집 메트릭을 `prometheus.remote_write`로 shared Prometheus에 push
- `external_labels`로 `environment`/`role`/`instance` 부착

### 2-3. 현재 들어오는 메트릭

| 출처 | 경로 | 상태 |
|---|---|---|
| EC2 컴포넌트(node/cadvisor/spring/redis/postgres) | Alloy push | ✅ |
| Kafka JMX | Prometheus 직접 scrape | ✅ |
| k6 부하 테스트 | `experimental-prometheus-rw` → `prom-dev` | ✅ |
| **K8s 클러스터(노드/Pod/워크로드)** | **없음** | ❌ |

---

## 3. 문제 정의 — K8s 메트릭 수집 갭

### 3-1. 핵심 문제

- K8s 클러스터에 **push 에이전트(Alloy)가 없어** 클러스터 메트릭이 shared Prometheus로 흐르지 않음
- `metrics-server`는 존재(HPA 동작 근거)하나, **순간값만 제공하고 시계열을 저장하지 않음** → 그래프 불가

### 3-2. 영향

- 카오스 실험 중 **서버사이드 시계열**(HPA replica 증감, Pod 수 변화, 컨테이너 CPU/메모리)을 그래프로 증빙 불가
- 클라이언트 메트릭(k6)만으로는 "원인-결과"(예: CPU 상승 → HPA scale-out) 연결 서술이 약함

### 3-3. 비목표

- 클러스터 내부 Prometheus/Grafana 신규 설치 (shared 스택 재사용으로 대체)
- 로그 파이프라인(Loki) K8s 통합 — 본 문서는 메트릭 우선, 로그는 후속

---

## 4. 설계 — Alloy DaemonSet + kube-state-metrics

### 4-1. 구성 개요

```
┌──────────────────────────────────────────────┐
│ v3 K8s 클러스터                                 │
│                                                │
│  ┌─────────────┐   scrape   ┌───────────────┐ │
│  │ Alloy        │◀───────────│ cadvisor      │ │
│  │ (DaemonSet,  │            │ (kubelet 내장) │ │
│  │  노드별 1개) │◀───────────│ node-exporter │ │
│  │             │◀───────────│ kube-state-   │ │
│  │             │   scrape   │ metrics (Deploy)│ │
│  └──────┬──────┘            └───────────────┘ │
│         │ remote_write (push)                  │
└─────────┼──────────────────────────────────────┘
          ▼  VPC Peering
   shared Prometheus (http://<HOST>:9090/api/v1/write)
          ▼
   Grafana (grafana.tasteam.kr)
```

### 4-2. 컴포넌트

| 컴포넌트 | 배포 형태 | 역할 |
|---|---|---|
| **Grafana Alloy** | DaemonSet | 노드별 메트릭 scrape + shared Prometheus로 remote_write push |
| **kube-state-metrics(KSM)** | Deployment | K8s 오브젝트 상태 메트릭(HPA/Pod/Deployment/PDB) 노출 |
| **node-exporter** | DaemonSet | 노드 하드웨어/OS 메트릭 (선택 — Alloy `exporter.unix`로 대체 가능) |
| cadvisor | kubelet 내장 | 컨테이너 메트릭 (별도 배포 불필요, kubelet `/metrics/cadvisor`) |

### 4-3. 수집 방식 — 기존 push 모델 계승

- Alloy가 클러스터 내부에서 **scrape** 후 → shared Prometheus로 **remote_write push** (기존 EC2와 동일 패턴)
- 클러스터 → shared 서버 방향 egress(VPC Peering) 필요 — 기존 EC2 push와 동일 네트워크 경로
- Alloy의 K8s scrape는 `discovery.kubernetes`(쿠버네티스 서비스 디스커버리)로 타겟 자동 발견

### 4-4. Alloy 설정 골격 (설계안)

```alloy
// kubelet cadvisor (컨테이너 메트릭)
discovery.kubernetes "nodes" {
  role = "node"
}

prometheus.scrape "cadvisor" {
  targets    = discovery.kubernetes.nodes.targets
  metrics_path = "/metrics/cadvisor"
  scheme       = "https"
  // kubelet 인증(serviceAccount 토큰) 설정
  forward_to = [prometheus.relabel.k8s.receiver]
}

// kube-state-metrics
prometheus.scrape "ksm" {
  targets    = [{ __address__ = "kube-state-metrics.monitoring.svc:8080" }]
  forward_to = [prometheus.relabel.k8s.receiver]
}

prometheus.remote_write "default" {
  endpoint {
    // HTTPS + basic_auth — k6(run-fi-steady.sh)와 동일한 수신 엔드포인트/인증
    url = "https://prom-dev.tasteam.kr/api/v1/write"
    basic_auth {
      username = sys.env("PROM_RW_USERNAME")   // tasteam
      password = sys.env("PROM_RW_PASSWORD")   // ExternalSecret 주입
    }
  }
  external_labels = {
    environment = "prod",
    role        = "k8s",
    instance    = sys.env("NODE_NAME"),   // DaemonSet downward API
  }
}
```

> **인증 확정**: `prom-dev`는 앞단 TLS + basic_auth 구조. 자격증명은 k6 스크립트(`run-fi-steady.sh` 16~19행)에 있는 값과 동일. Alloy도 동일하게 넣어야 push가 401 없이 도달한다. 운영에서는 비밀번호를 평문이 아닌 **ExternalSecret으로 주입**(기존 시크릿 스택 재사용).

---

## 5. 수집 대상 메트릭

### 5-1. 우선 수집 (카오스 실험 필수)

| 메트릭 출처 | 대표 메트릭 | 용도 |
|---|---|---|
| kube-state-metrics | `kube_horizontalpodautoscaler_status_current_replicas` | FI-08 HPA scale-out 그래프 |
| kube-state-metrics | `kube_deployment_status_replicas_available` | FI-06 가용 replica |
| kube-state-metrics | `kube_pod_status_phase`, `kube_pod_container_status_restarts_total` | FI-06 Pod 재스케줄/재시작 |
| kube-state-metrics | `kube_poddisruptionbudget_status_*` | FI-06 PDB 상태 |
| cadvisor | `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes` | FI-08 CPU, OOMKill |
| node-exporter | `node_cpu_seconds_total`, `node_memory_*` | 노드 리소스 압박 |

### 5-2. 후속 수집 (선택)

- Spring Actuator(`/actuator/prometheus`) — 앱 레벨 메트릭(서킷브레이커 상태 등 커스텀 메트릭이 노출되면 FI-09에 활용)
- Linkerd viz 메트릭 — 서비스 golden metrics(success rate/latency)

---

## 6. 라벨링 컨벤션 (기존 계승 + K8s 확장)

> 기존 `monitoring-labeling-convention.md`의 `environment`/`role`/`job`/`instance` 4축을 유지하고, K8s 차원만 추가.

### 6-1. 기존 4축 적용

| 라벨 | K8s에서의 값 | 부착 방식 |
|---|---|---|
| `environment` | `prod` | Alloy `external_labels` |
| `role` | **`k8s`** (신규 role 값 추가) | Alloy `external_labels` |
| `instance` | 노드명(`NODE_NAME`, downward API) | Alloy `external_labels` |
| `job` | `cadvisor` / `kube-state-metrics` / `node` | scrape 타겟 인라인 |

### 6-2. K8s 고유 차원 (KSM/cadvisor가 자동 부착)

- `namespace`, `pod`, `container`, `deployment`, `node` — 메트릭 자체에 포함되므로 별도 선언 불필요
- 드릴다운 경로: `environment=prod, role=k8s` → `namespace=app-prod` → `pod` → `container`

### 6-3. 주의

- 기존 EC2 메트릭과 `role`로 구분(`app`/`caddy`/... vs `k8s`) → Grafana에서 계열 혼동 방지
- `instance`가 EC2(호스트명)와 K8s(노드명)로 의미가 갈리므로, 대시보드 변수는 `role` 필터를 먼저 둘 것

---

## 7. GitOps 통합 (ArgoCD)

### 7-1. 배포 방식

- Alloy + kube-state-metrics를 **Helm 차트 → ArgoCD Application**으로 배포
- 네임스페이스: **`monitoring`** 신설 (05-kubeadm.md의 계획된 `monitoring` ns 실체화)

### 7-2. AppProject — 전용 프로젝트 신설 (결정)

- **결정**: 모니터링 전용 **AppProject `tasteam-monitoring`** 신설 (카오스 `tasteam-chaos`와 동일 패턴)
- 사유: KSM이 클러스터 전역 read 권한(ClusterRole) 필요 → 앱 배포용 `tasteam` 프로젝트에 전역 권한을 섞지 않고 격리
- `clusterResourceWhitelist`에 KSM ClusterRole/ClusterRoleBinding 허용, `destinations`는 `monitoring` ns로 제한
- 권한 에러 발생 시 그때 화이트리스트를 점진 조정(진행을 막지 않음)

### 7-3. 배치 (구현됨)

```
v3-k8s/
├── argocd/
│   ├── projects/
│   │   └── tasteam-monitoring-project.yaml   # 전용 AppProject
│   └── apps/
│       ├── monitoring-resources.yaml         # ns/ExternalSecret/RBAC (wave 0)
│       ├── kube-state-metrics.yaml           # KSM helm multi-source (wave 1)
│       └── alloy.yaml                        # Alloy helm multi-source (wave 2)
├── manifests/
│   ├── monitoring/
│   │   ├── namespace.yaml
│   │   ├── external-secret.yaml
│   │   ├── alloy-cadvisor-rbac.yaml
│   │   └── README.md                         # 설치/검증 절차
│   └── helm/values/
│       ├── alloy.yaml                        # Alloy config(remote_write) 포함
│       └── kube-state-metrics.yaml
```

- helm Application은 **multi-source** — chart(외부 repo, 버전 핀) + 이 repo의 values를 `$values`로 참조
- 버전 핀: alloy `1.0.3`, kube-state-metrics `5.18.0`
- sync-wave로 순서 보장: resources(자격증명) → KSM → Alloy

### 7-4. 시크릿/설정

- remote_write 엔드포인트: `https://prom-dev.tasteam.kr/api/v1/write` (HTTPS + basic_auth, 확정)
- **basic_auth 자격증명** — k6 스크립트(`run-fi-steady.sh`)의 값과 동일 (HTTPS + basic_auth 확정)
  - username/password를 **ExternalSecret으로 주입** — 기존 external-secrets 스택 재사용, 매니페스트·문서에 평문 금지

---

## 8. 검증 방법

1. **Alloy 기동 확인** — DaemonSet이 모든 노드에 1개씩 Running
2. **remote_write 도달 확인** — shared Prometheus에서 `up{role="k8s"}` 쿼리로 타겟 수신 확인
3. **KSM 메트릭 확인** — `kube_horizontalpodautoscaler_status_current_replicas{namespace="app-prod"}` 값 조회
4. **Grafana 시각화 확인** — `grafana.tasteam.kr`에서 `role=k8s` 필터로 노드/Pod 메트릭 그래프 표출
5. **카오스 연계 스모크** — FI-06 1회 주입 후 Grafana에서 Pod 수 변화가 시계열로 잡히는지 확인

---

## 9. 카오스 엔지니어링 연계

> 본 모니터링 통합은 [chaos-mesh-l2-design.md](fault-injection/chaos-mesh/chaos-mesh-l2-design.md)의 관측 전제. 각 FI 시나리오가 요구하는 그래프를 본 구성이 공급한다.

| FI 시나리오 | 필요 그래프 | 공급 메트릭 |
|---|---|---|
| FI-06 (Pod 축출) | Pod 수/재스케줄 시간, PDB 상태 | KSM `kube_pod_*`, `kube_poddisruptionbudget_*` |
| FI-07 (네트워크 지연) | p95/p99 레이턴시 | k6(기존) + Linkerd viz(후속) |
| FI-08 (HPA) | replica 증감, CPU 사용률 | KSM HPA + cadvisor CPU |
| FI-09 (서킷브레이커) | 서킷 상태, 주 경로 5xx | Spring Actuator(후속) + k6 |

- **선후 관계**: 본 모니터링 통합 → 카오스 게임데이 순서. Baseline 측정도 본 구성 완료 후 수행
- 클라이언트(k6) + 서버(K8s) 메트릭을 **동일 Grafana**에서 시점 정렬 → "부하→스케일→회복" 인과를 한 화면에 증빙

---

## 10. 리스크 및 오픈 이슈

| # | 항목 | 영향 | 대응 |
|---|---|---|---|
| M1 | 클러스터→shared 서버 egress(VPC Peering) | push 미도달 | 기존 EC2 push와 동일 경로 확인, 보안그룹/NACL 점검 |
| M2 | KSM ClusterRole(전역 read) | AppProject 권한 충돌 | 7-2 — clusterResourceWhitelist 조정 |
| M3 | shared Prometheus 카디널리티 증가 | 저장/성능 부하 | K8s 메트릭 relabel로 불필요 라벨 drop, scrape 대상 선별 |
| M4 | `instance` 라벨 의미 혼재(EC2 vs K8s 노드) | 대시보드 혼동 | 6-3 — `role` 우선 필터 |
| M5 | kubelet cadvisor 인증 | scrape 실패 | serviceAccount 토큰 + TLS 설정 |
| M6 | shared 서버 SPOF | 모니터링 전체 중단 | 기존 운영 리스크 승계(본 문서 범위 외, 별도 HA 과제) |

### 10-1. 결정 대기

- [ ] node-exporter 별도 배포 vs Alloy `exporter.unix` 내장 사용
- [ ] Linkerd viz / Spring Actuator 수집 포함 시점(본 차수 vs 후속)

> 결정 완료: ~~AppProject 권한~~ → 전용 `tasteam-monitoring` 신설(7-2), ~~shared Prometheus 인증~~ → basic_auth(`tasteam`/`tasteam-k6-metrics`), ExternalSecret 주입(4-4, 7-4)
