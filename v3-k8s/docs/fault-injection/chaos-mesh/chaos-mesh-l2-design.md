# Chaos Mesh 기반 애플리케이션 레이어 카오스 엔지니어링 설계 (L2)

> 작성 기준일: 2026-06-29
> 목표 성숙도: **L2 — 선언적 게임데이(Declarative Game Day)**
> 도구: **Chaos Mesh 단일 스택**
> 선행 작업: FI-04(AZ 장애), FI-05(etcd 리더 손실) — AWS FIS 기반 인프라 레이어 검증 완료

---

## 목차

1. [개요 및 목표 수준](#1-개요-및-목표-수준)
2. [검증 목표 (Verification Objectives)](#2-검증-목표-verification-objectives)
3. [범위 / 비범위](#3-범위--비범위)
4. [도구 선택 근거 — 왜 Chaos Mesh인가](#4-도구-선택-근거--왜-chaos-mesh인가)
5. [아키텍처](#5-아키텍처)
6. [GitOps 통합 설계 (핵심)](#6-gitops-통합-설계-핵심)
7. [안전장치 — 블래스트 반경과 중단 조건](#7-안전장치--블래스트-반경과-중단-조건)
8. [Linkerd 서비스 메시 상호작용 주의](#8-linkerd-서비스-메시-상호작용-주의)
9. [시나리오 카탈로그 (FI-06 ~ FI-09)](#9-시나리오-카탈로그-fi-06--fi-09)
10. [게임데이 운영 절차](#10-게임데이-운영-절차)
11. [산출물 / 디렉토리 구조 제안](#11-산출물--디렉토리-구조-제안)
12. [로드맵 — L2에서 L3로의 전이 조건](#12-로드맵--l2에서-l3로의-전이-조건)
13. [리스크 및 오픈 이슈](#13-리스크-및-오픈-이슈)

---

## 1. 개요 및 목표 수준

### 1-1. 목표

- K8s **애플리케이션 레이어**(Pod / 네트워크 / 리소스)의 장애 내성을 선언적·재현 가능한 형태로 검증
- 기존 FI-04/05의 runbook·보고서 체계를 그대로 계승 — 일관된 증적 관리

### 1-2. 성숙도 좌표 — 왜 L2인가

- 카오스 성숙도는 **정교함(Sophistication)** 축과 **적용 범위(Adoption)** 축으로 구분
- 본 설계의 목표는 정교함 축의 **L2** 고정 — 아래 표 참조

| 단계 | 정교함 | 핵심 능력 | 본 설계 |
|---|---|---|---|
| L1 실험적 | 수동, ad-hoc | runbook, 수동 관측 | FI-04/05에서 완료(인프라) |
| **L2 선언적 게임데이** | **CRD 선언, 사람이 판정** | **재현 가능 실험 정의 + 대시보드** | **← 본 설계 목표** |
| L3 검증 자동화 | probe 자동 pass/fail, CI 게이트 | steady-state probe | 로드맵(12장) |
| L4 상시·연속 | 스케줄·자동 abort·SLO 연동 | blast radius 자동 제어 | 범위 외 |

- L2의 정의: **실험은 선언적(CRD)으로 재현 가능하되, 가설의 합격 여부는 사람이 대시보드/관측으로 판정**
- probe 기반 자동 판정·CI 회귀 게이트는 L3 영역 → 본 설계에서는 *전이 가능하도록 구조만 열어둠*(12장)

---

## 2. 검증 목표 (Verification Objectives)

> 본 장은 "무엇을 검증하려 하는가"를 시나리오와 분리해 명시. 각 목표(VO)는 9장의 시나리오로 실현되며, 현 클러스터에 **실제로 구현된 메커니즘**에 매핑된다.

### 2-1. 검증 목표 매트릭스

| VO | 검증 질문 | 보호/회복 메커니즘 (현 구현 위치) | 실현 시나리오 |
|---|---|---|---|
| **VO-1** | **파드가 축출/종료된 후 재스케줄이 문제 없이 일어나는가** — 진행 중 요청 손실 없이 | PDB `spring-boot-pdb`(minAvailable=1) + ReplicaSet 재스케줄 + Linkerd retry | **FI-06** |
| **VO-2** | **서킷브레이커가 정상 작동하는가** — 외부 의존성 장애 시 OPEN 전이 → graceful degradation → 복구 | 커스텀 CB: `EmailCircuitBreaker`(3회/300s), `FcmCircuitBreaker`(5회/60s), `UserActivityDispatchCircuitBreaker`(5회/60s) | **FI-09** |
| **VO-3** | **HPA가 작동하여 요청이 타임아웃 전에 처리되는가** — 부하 급증 시 파드 스케일아웃이 제때 일어나는가 | HPA `spring-boot-hpa`(70%, 2~4) *(CA는 본 차수 제외 — 3-2 참조)* | **FI-08** |

### 2-2. 각 검증 목표의 상세 가설

- **VO-1 (파드 축출/재스케줄)**
  - 자발적 중단(voluntary, 예: drain·node pressure 축출)과 비자발적 종료(involuntary, 예: pod-kill) 모두에서
  - PDB가 동시 가용 pod 수를 `minAvailable=1` 이상으로 보장하고, ReplicaSet이 즉시 신규 pod를 재스케줄하며
  - 축출 순간 진행 중이던 요청은 Linkerd retry/재시도로 흡수되어 **사용자 체감 5xx로 전파되지 않는다**

- **VO-2 (서킷브레이커)**
  - 보호 대상은 **클러스터 외부 의존성** — SMTP(이메일), Firebase FCM(푸시), analytics 수집 엔드포인트
  - 해당 의존성에 장애가 주입되면 연속 실패가 임계에 도달해 서킷이 **OPEN**으로 전이하고
  - OPEN 동안 발송을 **스킵**(`"...Circuit Breaker OPEN. 발송 스킵"`)하여 **주 API 요청 경로는 정상 동작**(graceful degradation)하며
  - `open-duration` 경과 후 의존성이 복구되면 `recordSuccess`로 서킷이 **CLOSE**로 회복된다
  - 핵심: 서킷브레이커가 **장애를 격리**하여 알림 경로 장애가 주 서비스로 전파되지 않음을 확인

- **VO-3 (HPA 스케일아웃)**
  - 부하 급증 → CPU 사용률이 HPA 임계(70%) 초과 → HPA가 replica를 `2→최대 4`로 확장
  - 신규 replica가 **기존 노드 용량 내에서** 스케줄되어, **확장 연쇄가 요청 타임아웃 한도 내에 완료**되는가를 검증
  - 부하 해소 후 HPA scale-in으로 정상 축소되는가까지 확인
  - **Cluster Autoscaler(노드 증설)는 본 차수 제외** — CA가 현재 정상 동작하지 않아, 실험이 CA 미동작에 막혀 HPA 검증까지 오염되는 것을 방지. 따라서 부하 강도는 **기존 노드 용량을 초과하지 않는 선**으로 제한(pending pod 미발생 목표)

### 2-3. 검증 목표 ↔ 시나리오 ↔ 장애 유형 매핑

| VO | 시나리오 | Chaos Mesh 유형 | 주 관측 지표 |
|---|---|---|---|
| VO-1 | FI-06 | PodChaos (pod-kill / pod-failure) | PDB 위반 여부, 재스케줄 시간, 5xx |
| VO-2 | FI-09 | NetworkChaos (외부 의존성 partition) | 서킷 상태 전이, 알림 degrade, 주 경로 5xx |
| VO-3 | FI-08 | StressChaos (CPU) | HPA replica, p99, (pending pod=0 유지 확인) |

---

## 3. 범위 / 비범위

### 3-1. 범위 (In Scope)

- Chaos Mesh 설치 및 GitOps 편입 설계
- 4개 검증 시나리오 — **PodChaos / NetworkChaos / StressChaos** 조합으로 VO-1~3 실현
- 대상 워크로드 — `spring-boot`(API), `fastapi`(AI)
- 검증 메커니즘 — **PDB, HPA, 커스텀 서킷브레이커, Linkerd**
- 실험 환경 — **prod 단독** (본 차수 결정). 통제된 게임데이로만 수행 → 안전장치(7장) 비중이 커짐
- 안전장치(블래스트 반경·중단조건·RBAC) 설계
- 시나리오 카탈로그(FI-06~09) 및 게임데이 절차

### 3-2. 비범위 (Out of Scope)

- **인프라 레이어 장애**(노드/AZ/etcd) — 기존 **AWS FIS** 유지, Chaos Mesh로 이관하지 않음
- **Cluster Autoscaler(노드 증설) 검증** — CA가 현재 정상 동작하지 않아 본 차수 제외. CA 자체 결함 수정은 별도 트랙. VO-3은 HPA 스케일아웃까지만 검증
- probe 기반 자동 가설검증·CI 파이프라인 통합 (L3)
- 프로덕션 상시 자동 카오스·SLO 연동 자동중단 (L4)
- IOChaos / DNSChaos / TimeChaos / HTTPChaos — 본 차수 제외(추후 확장 후보)

### 3-3. 레이어별 도구 이원화 원칙

| 레이어 | 장애 대상 | 도구 | 비고 |
|---|---|---|---|
| 인프라 | 노드 / AZ / etcd | **AWS FIS** | FI-04/05, 변경 없음 |
| 애플리케이션 | Pod / 네트워크 / 리소스 | **Chaos Mesh** | 본 설계 |

- 두 레이어를 단일 도구로 통합하려 시도하지 않음 — 각 레이어의 주입 지점·권한 모델이 다름

---

## 4. 도구 선택 근거 — 왜 Chaos Mesh인가

### 4-1. L2 요구 능력 대비 적합성

| L2 요구 능력 | Chaos Mesh | LitmusChaos | 판정 |
|---|---|---|---|
| CRD 선언적 실험 | ✅ 1급 | ✅ 1급 | 동등 |
| 대시보드(관측·수동 판정) | ✅ 내장 Dashboard | △ ChaosCenter(무거움) | **Chaos Mesh 우세** |
| 학습/운영 비용 | 낮음 | 높음(워크플로우·hub) | **Chaos Mesh 우세** |
| kubeadm 호환 | ✅ 무난 | ✅ | 동등 |
| Pod/Network/Stress 지원 | ✅ 전부 | ✅ 전부 | 동등 |

- L2에서는 LitmusChaos의 강점(워크플로우 엔진·ChaosHub·probe)이 **아직 불필요한 오버헤드**
- 단일 스택 유지 → L3 전이 시에도 Chaos Mesh의 `Workflow` + `StatusCheck`로 확장 가능(12장)

### 4-2. 기존 스택과의 정합성

- CRD 기반 → ArgoCD GitOps로 선언 관리 가능
- Dashboard로 게임데이 중 실시간 관측 → FI-04/05의 "사람이 health loop 관측" 패턴과 일치

---

## 5. 아키텍처

### 5-1. 컴포넌트 구성

```
┌─────────────────────────────────────────────────────────┐
│ namespace: chaos-mesh                                     │
│  - chaos-controller-manager (실험 오케스트레이션)         │
│  - chaos-daemon (DaemonSet, 각 노드에서 실제 주입)        │
│  - chaos-dashboard (관측·수동 판정 UI)                    │
└─────────────────────────────────────────────────────────┘
         │ 실험 CR(PodChaos/NetworkChaos/StressChaos) 적용
         ▼
┌─────────────────────────────────────────────────────────┐
│ namespace: app-dev / app-stg / app-prod                  │
│  - spring-boot (Deployment, PDB minAvailable=1, HPA 2~4) │
│  - fastapi    (Deployment, HPA)                          │
│  - Linkerd sidecar (각 pod에 주입)                        │
│  - 커스텀 서킷브레이커 (Email/FCM/Analytics, 외부 의존성) │
│  - HPA (CPU 70%, replica 2~4) — 노드 용량 내 스케일아웃   │
└─────────────────────────────────────────────────────────┘

  ※ Cluster Autoscaler(노드 증설)는 본 차수 제외 (CA 미동작)
```

### 5-2. 핵심 컴포넌트 특성

- **chaos-daemon** — 특권(privileged) DaemonSet. 노드의 `/proc`, `tc`, `iptables`에 접근하여 주입 → 보안 관점에서 RBAC·PSA 검토 필요(7장)
- **chaos-dashboard** — Ingress 노출 시 인증 필수. 내부망 한정 권장
- 실험 CR — `namespaceSelector`로 대상 네임스페이스를 명시적으로 제한

### 5-3. 네임스페이스 전략

| 네임스페이스 | 용도 |
|---|---|
| `chaos-mesh` | Chaos Mesh 컨트롤 플레인 설치 |
| `app-prod` | **실험 대상 (본 차수 단독)** — 통제된 게임데이로만 |

- prod 단독 대상 → 블래스트 반경 통제가 핵심. 모든 실험은 `mode: one` + 저트래픽 시간대 + kill switch 대기 (7장)
- 실험 CR 자체의 거주 네임스페이스 결정은 6-3절 참조

---

## 6. GitOps 통합 설계 (핵심)

> 본 장이 본 설계에서 가장 주의가 필요한 부분. 기존 ArgoCD 설정과 직접 충돌하는 지점이 있음.

### 6-1. 발견된 제약 — AppProject 화이트리스트

- 현재 `argocd/projects/tasteam-project.yaml`의 `namespaceResourceWhitelist`는 다음만 허용:
  - `""`(core), `apps`, `autoscaling`, `networking.k8s.io`, `policy`, `external-secrets.io`
- **`chaos-mesh.org` group이 화이트리스트에 없음** → 카오스 실험 CR을 `tasteam` 프로젝트로 동기화하면 ArgoCD가 **거부**
- 또한 `ResourceQuota`/`LimitRange`는 blacklist — 무관하나 정책 엄격함을 시사

### 6-2. 결정 — 카오스 전용 AppProject 분리

- 카오스 리소스를 `tasteam` 프로젝트에 섞지 않고 **별도 AppProject `tasteam-chaos`** 신설
- 사유:
  - 권한 경계 분리 — 카오스 CR 생성 권한과 앱 배포 권한을 격리
  - blast radius 통제 — 카오스 프로젝트의 `destinations`를 dev/stg로 우선 제한, prod는 명시적 추가
  - 앱 배포 파이프라인과 카오스 실험의 **동기화 정책 독립**

```yaml
# 제안: argocd/projects/tasteam-chaos-project.yaml (설계안, 미적용)
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: tasteam-chaos
  namespace: argocd
spec:
  description: "Tasteam 카오스 엔지니어링 실험 프로젝트"
  sourceRepos:
    - "https://github.com/100-hours-a-week/3-team-Tasteam-cloud.git"
  destinations:
    - server: https://kubernetes.default.svc
      namespace: chaos-mesh
    - server: https://kubernetes.default.svc
      namespace: app-prod   # 본 차수 실험 대상(단독)
  namespaceResourceWhitelist:
    - group: chaos-mesh.org
      kind: "*"
```

### 6-3. 실험 CR의 GitOps 적용 방식 — 두 모델

| 모델 | 방식 | 장점 | 단점 | 권장 |
|---|---|---|---|---|
| **A. GitOps 관리형** | 실험 CR을 Git에 두고 ArgoCD가 동기화 | 증적·이력 Git 추적 | "상시 카오스"처럼 보임, 실험 종료 후 drift | dev/stg 상시 회복력 점검용 |
| **B. 게임데이 임시형** | 게임데이 시 `kubectl apply`로 직접 주입, Git엔 카탈로그만 | 통제·승인 명확 | 이력은 별도 보고서로 | **prod 게임데이 권장** |

- **결정**: L2에서는 **모델 B 기본**(게임데이 = 통제된 일회성), 실험 정의(YAML)는 Git에 카탈로그로 보관
- ArgoCD가 게임데이 중 주입된 CR을 drift로 오인하지 않도록, 카탈로그 경로는 **Application source에서 제외**하거나 별도 미동기화 디렉토리에 보관

### 6-4. 설치 방식

- Chaos Mesh는 Helm 차트 → ArgoCD Application(`tasteam-chaos` 프로젝트, `chaos-mesh` 네임스페이스)으로 **설치 자체는 GitOps 관리**
- 실험 CR(모델 B)과 설치(GitOps)를 분리 — 설치는 선언적, 실험은 통제적

---

## 7. 안전장치 — 블래스트 반경과 중단 조건

### 7-1. 블래스트 반경 제어 (다층)

1. **prod 단독 — 강도 단계화** — prod에서 수행하므로 환경 승급이 아닌 **주입 강도**를 단계화(약→강), 저트래픽 시간대에 게임데이 한정
2. **네임스페이스 스코프** — controller-manager를 `targetNamespace: app-prod` 제한 모드로 설치 권장(타 ns 주입 차단)
3. **selector 명시** — 모든 실험 CR은 `namespaceSelector` + `labelSelector` 필수, 와일드카드 금지
4. **mode/value** — prod이므로 **`mode: one` 고정**(또는 소수 `fixed-percent`), `mode: all` 절대 금지
5. **duration 필수** — 모든 실험에 `duration` 명시(무기한 주입 금지)
6. **사전 리허설(선택)** — 필요 시 동일 CR을 dev/stg에 1회 dry-run 후 prod 실행(승인자 판단)

### 7-2. 중단 조건 (Abort) — FI-04/05 패턴 계승

- FI-04/05의 **CloudWatch Alarm 자동중단** 패턴을 애플리케이션 레이어로 확장
- L2(수동 판정)이므로 **1차 중단은 사람이 수행** — 아래 조건 충족 시 즉시 `kubectl delete` 또는 dashboard에서 pause

| 중단 트리거 | 임계 | 관측 수단 |
|---|---|---|
| API 5xx 비율 | > 5% (1분) | health loop / 메트릭 |
| p99 레이턴시 | 기준치 3배 초과 | 메트릭 |
| PDB 위반(가용 pod < minAvailable) | 발생 즉시 | `kubectl get pdb` |
| 서킷브레이커 비복구 | open-duration 2배 경과 후에도 OPEN | 앱 로그/메트릭 |
| pending pod 발생(FI-08) | 1개라도 발생 시 | `kubectl get pods` — 부하 강도 과다 신호, 즉시 강도 하향 |
| 실험 미해제 pod 잔존 | duration 초과 후 | dashboard |

- **긴급 정지(kill switch)**: `kubectl delete podchaos,networkchaos,stresschaos --all -n <ns>` — 게임데이 runbook 최상단 고정

### 7-3. RBAC / 보안

- chaos-daemon은 privileged → 노드 단위 권한. 실험 주입 권한은 **전용 ServiceAccount**로 최소화
- chaos-dashboard 접근 — RBAC 토큰 기반, 외부 노출 금지(내부망/포트포워딩)
- 실험 생성 권한 — 운영자 그룹으로 제한, 일반 배포 권한과 분리(6-2의 프로젝트 분리와 연동)

---

## 8. Linkerd 서비스 메시 상호작용 주의

> 현 클러스터는 Linkerd sidecar가 모든 app pod에 주입되어 있고, NetworkPolicy로 proxy 통신 경로가 고정됨. 네트워크 카오스 설계에 직접 영향.

### 8-1. NetworkChaos × Linkerd

- Chaos Mesh NetworkChaos는 `tc`/`iptables` 기반으로 pod netns에 주입
- Linkerd proxy(`4143` 등)가 트래픽을 가로채므로, **주입 대상이 app 컨테이너인지 sidecar 경유 트래픽인지 명확히 해야** 함
- Linkerd가 제공하는 **retry·timeout·mTLS**가 네트워크 장애를 일부 흡수 → 이는 *검증 대상*이자 *결과 해석의 변수*
  - 가설을 "Linkerd 회복력 포함 서비스가 지연을 견디는가"로 명시해야 결과가 유의미

### 8-2. NetworkPolicy 간섭

- `networkpolicy.yaml`이 egress/ingress를 명시적으로 제한 → NetworkChaos의 `partition`(네트워크 단절) 실험 시 이미 차단된 경로와 혼동 가능
- partition 실험은 **NetworkPolicy가 허용하는 경로**에 한정해 설계해야 결과가 깨끗함

### 8-3. 서킷브레이커(VO-2)와 외부 의존성 타겟팅

- 커스텀 서킷브레이커가 보호하는 대상(SMTP·FCM·analytics)은 **클러스터 외부** → NetworkChaos `externalTargets`(외부 도메인/IP) 또는 egress 차단으로 장애 주입
- Linkerd는 클러스터 내부 mesh 트래픽만 처리 → 외부 의존성 차단은 **메시 밖 egress 경로** 대상이므로 8-1의 sidecar 간섭과 분리해 설계
- 즉 VO-2 실험은 "외부 egress partition", VO-1/지연 실험은 "메시 내부 트래픽"으로 **타겟 경로를 구분**

### 8-4. 권고

- 첫 NetworkChaos는 **단순 latency**부터(partition·loss는 이후 차수)
- sidecar 주입된 pod 대상 실험은 **dev에서 Linkerd 동작 영향을 먼저 관측** 후 stg 승급

---

## 9. 시나리오 카탈로그 (FI-06 ~ FI-09)

> 명명 규칙은 기존 FI 시리즈를 계승(FI-04/05 다음 번호). 각 시나리오는 추후 개별 runbook으로 상세화.

### 9-0. 측정 지표 공통 규약 & 관측 스택

> 포트폴리오용 정량 증적을 위해, 모든 시나리오는 **Baseline → 장애 중 → 회복 후** 3점을 측정한다. 각 시나리오 하단 "측정 지표" 표는 **실측 시 값을 채우는 템플릿**이다(현재는 빈칸 `_`).

#### 관측 스택 (이미 구성됨)

| 도구 | 측정 대상 | 추출 방법 |
|---|---|---|
| **k6** (`scripts/loadtest/fi-steady-load.js`) | 5xx율·레이턴시·RPS, SLO PASS/FAIL | 임계값 내장(`fi_error_rate<0.05`, `fi_latency p95<3000`) → 종료 시 자동 판정 |
| **Prometheus** (k6 remote-write) | k6 메트릭 시계열 | `run-fi-steady.sh`가 RW 전송 |
| **Grafana** | 시계열 그래프(증적 캡처) | 장애 주입 시점 마커 + 곡선 |
| **Linkerd viz** | per-service golden metrics(success rate·p50/95/99·RPS) | `linkerd viz stat`, Grafana |
| **Chaos Mesh dashboard** | 실험 타임라인(주입/해제 시각) | MTTR delta 산출 기준 |
| **kubectl** | pod/hpa/pdb 상태·이벤트 타임스탬프 | `-w` watch + 이벤트 시각 |

#### 측정 원칙

- **Baseline 선측정 필수** — 장애 없는 정상 상태의 5xx·p95·RPS를 k6로 먼저 1회 측정(없으면 "장애 중에도 유지" 주장 불가)
- **MTTR = 이벤트 타임스탬프 delta** — Chaos Mesh dashboard 주입 시각 ~ 회복 이벤트 시각
- **SLO 환산** — 모든 결과는 "가용성 99.x%, p95 < 3s 충족" 형태로 보고서에 환산 기재

### FI-06. PodChaos — Pod 축출 후 재스케줄 검증 (VO-1)

| 항목 | 내용 |
|---|---|
| 장애 유형 | `PodChaos` / `action: pod-kill` (+ 보강: `pod-failure`로 일시 unready 재현) |
| 대상 | `app-prod` 네임스페이스 `app=spring-boot` |
| 가설 | spring-boot pod가 축출/종료돼도 **PDB(minAvailable=1)**가 가용성을 보장하고, ReplicaSet이 즉시 재스케줄하며, 축출 순간 진행 중 요청이 Linkerd retry로 흡수되어 5xx가 임계 이하다 |
| 주입 파라미터 | `mode: one`, `duration: 60s` |
| steady-state | 5xx < 1%, ready replica ≥ 2 |
| 관측 | dashboard, `kubectl get pod -w`, `kubectl get pdb -w`, health loop |
| 합격 기준 | PDB 위반 없음 · 재스케줄 완료(목표 시간 내) · 진행중 요청 무손실 · 5xx < 5% |
| 위험 | 동시 다발 종료 금지(`mode: all` 절대 불가) |
| 비고 | 자발적 축출(drain) 관점 추가 검증은 게임데이에서 `kubectl drain`을 보조 수단으로 병행 가능 |

**측정 지표** _(실측 시 값 기입)_

| 지표 | Baseline | 장애 중 | 회복 후 | 목표 | 측정 도구 |
|---|---|---|---|---|---|
| 5xx 비율 | `_` | `_` | `_` | < 5% | k6 `fi_error_rate` / Linkerd |
| 가용성 % | `_` | `_` | `_` | 99.x% 유지 | k6 summary |
| p95 레이턴시(ms) | `_` | `_` | `_` | < 3000 | k6 `fi_latency` |
| **재스케줄 시간(s)** (kill→Ready) | — | `_` | — | < 30 | Chaos dashboard + `kubectl get pod -w` |
| PDB 위반 횟수 | 0 | `_` | 0 | 0 | `kubectl get pdb` |
| 블래스트 반경(영향 pod/전체) | — | `_`/4 | — | 1/4 | `mode: one` |

### FI-07. NetworkChaos — Spring Boot ↔ FastAPI 지연 주입

| 항목 | 내용 |
|---|---|
| 장애 유형 | `NetworkChaos` / `action: delay` |
| 대상 | `spring-boot` → `fastapi-svc` 방향 트래픽(메시 내부) |
| 가설 | 서비스 간 통신에 지연(예: 200ms±50ms)이 발생해도, Linkerd timeout/retry와 앱 타임아웃 설정이 이를 처리하여 사용자 체감 장애로 전파되지 않는다 |
| 주입 파라미터 | `latency: 200ms`, `jitter: 50ms`, `direction: to`, `duration: 120s`, `mode: all`(대상 한정) |
| steady-state | p99 레이턴시 기준치 내, 5xx < 1% |
| 관측 | dashboard, 메트릭(p50/p99), Linkerd 메트릭 |
| 합격 기준 | 타임아웃 폭주 없음 · 회복 후 레이턴시 정상화 |
| 주의 | 8장(Linkerd/NetworkPolicy) 선반영 필수 |

**측정 지표** _(실측 시 값 기입)_

| 지표 | Baseline | 장애 중 | 회복 후 | 목표 | 측정 도구 |
|---|---|---|---|---|---|
| 주입 지연(ms) | — | 200±50 | — | 설정값 | NetworkChaos CR |
| **체감 p95/p99(ms)** | `_` | `_` | `_` | SLO 내(p95<3000) | k6 / Linkerd |
| 5xx 비율 | `_` | `_` | `_` | < 1% | k6 / Linkerd success rate |
| 타임아웃·retry 발생 | `_` | `_` | `_` | 폭주 없음 | Linkerd viz |
| 회복 후 p95 정상화 시간(s) | — | — | `_` | 신속 복귀 | Linkerd 시계열 |

### FI-08. StressChaos — HPA 스케일아웃 검증 (VO-3)

| 항목 | 내용 |
|---|---|
| 장애 유형 | `StressChaos` / CPU |
| 대상 | `app-prod` `spring-boot` pod (부하 발생원), 동반: 부하 생성기(`scripts/loadtest`) 병행 |
| 가설 | 부하 급증으로 CPU 사용률이 **HPA 임계(70%)**를 초과하면 HPA가 replica를 `2→최대 4`로 확장하고, 신규 replica가 **기존 노드 용량 내에서 스케줄**되어 **요청이 타임아웃 한도 내에 정상 처리**된다. 부하 해소 후 HPA scale-in으로 정상 축소된다 |
| 주입 파라미터 | `stressors.cpu.workers: N`, `load: 80`, `duration: 300s`, `mode: one`(+ 부하 생성기로 트래픽 증대) |
| steady-state | OOMKill 없음, 요청 처리 지속, 타임아웃 내 응답, **pending pod 0 유지** |
| 관측 | `kubectl get hpa -w`, `kubectl get pods -w`, dashboard, p99 |
| 합격 기준 | HPA scale-out 발생(2→최대 4) · **타임아웃 초과 요청 0건** · **pending pod 미발생** · 부하 해소 후 scale-in |
| 위험 | 부하 과다 시 pending pod 발생 → CA 미동작으로 미해소 위험. **부하 강도를 노드 용량 내로 제한**하고 pending 발생 시 즉시 중단(7-2) |
| 비고 | **Cluster Autoscaler 검증은 제외**(CA 미동작, 3-2). 본 시나리오는 HPA 스케일아웃이 타임아웃 내 완료되는지에 집중 |

**측정 지표** _(실측 시 값 기입)_

| 지표 | Baseline | 장애 중 | 회복 후 | 목표 | 측정 도구 |
|---|---|---|---|---|---|
| CPU 사용률 peak(%) | `_` | `_` | `_` | > 70 유도 | metrics-server / Grafana |
| **HPA 반응 시간(s)** (70%→scale 시작) | — | `_` | — | < 30 | `kubectl get hpa -w` 이벤트 |
| replica 수 | 2 | `_` | 2 | 2→최대4→2 | `kubectl get deploy -w` |
| **처리량 RPS** (scale 전/후) | `_` | `_` | `_` | 증가 | k6 / Linkerd |
| 타임아웃 초과 건수 | 0 | `_` | 0 | **0** | k6 |
| pending pod 수 | 0 | `_` | 0 | **0**(CA 제외) | `kubectl get pods` |
| scale-in 소요(s) | — | — | `_` | 정상 축소 | `kubectl get hpa` |

### FI-09. NetworkChaos — 서킷브레이커 작동 검증 (VO-2)

| 항목 | 내용 |
|---|---|
| 장애 유형 | `NetworkChaos` / `action: partition` 또는 `delay`(타임아웃 유발) — **외부 의존성 대상** |
| 대상 | spring-boot → **외부 egress**: SMTP(이메일), Firebase FCM, analytics 수집 엔드포인트 (`externalTargets`) |
| 가설 | 외부 의존성이 차단되면 연속 실패가 임계(Email 3 / FCM 5 / Analytics 5)에 도달해 서킷이 **OPEN**으로 전이하고, OPEN 동안 발송을 **스킵**하여 주 API 요청 경로는 정상 동작하며(graceful degradation), `open-duration`(Email 300s / FCM·Analytics 60s) 경과 후 의존성 복구 시 **CLOSE로 회복**된다 |
| 주입 파라미터 | `action: partition`, `direction: to`, `externalTargets: [<smtp/fcm/analytics 엔드포인트>]`, `duration: 의존성별 open-duration보다 길게` |
| steady-state | 주 API 5xx < 1%, 정상 시 알림 발송 성공 |
| 관측 | 앱 로그(`"Circuit Breaker OPEN ... 발송 스킵"`), CB 메트릭/상태, 주 경로 health loop |
| 합격 기준 | 임계 도달 시 OPEN 전이 · OPEN 중 **주 경로 5xx 미증가**(격리 성공) · 차단 해제 후 open-duration 경과 시 CLOSE 회복 · 누락 알림은 outbox/재시도로 보전(설계 확인) |
| 위험 | 외부 egress 차단이 다른 정상 트래픽에 영향 없도록 `externalTargets`를 의존성 IP/도메인으로 한정 |
| 비고 | Email/FCM/Analytics 3개 의존성을 **개별 실험**으로 분리(임계·open-duration이 다름) |

**측정 지표** _(실측 시 값 기입 — 의존성별로 별도 작성)_

| 지표 | Baseline | 장애 중 | 회복 후 | 목표 | 측정 도구 |
|---|---|---|---|---|---|
| **OPEN 전이 시간(s)** | — | `_` | — | 임계 도달 시(예 Email 3회) | 앱 로그 타임스탬프 |
| **주 API 5xx 증가분(격리)** | `_` | `_` | `_` | **0**(완전 격리) | k6 / Linkerd |
| 알림 발송 스킵 건수 | 0 | `_` | 0 | OPEN 중 스킵 | 앱 로그 |
| **서킷 복구 시간 MTTR(s)** (OPEN→CLOSE) | — | `_` | `_` | open-duration 기반(Email300/FCM·Analytics60) | 앱 로그 delta |
| 누락 알림 보전 건수 | — | — | `_` | outbox 재처리(R9 확인) | 앱 로그 / DB |

### 9-1. 공통 실험 메타데이터

- 모든 시나리오 CR에 다음 라벨 부착 — 증적 추적용
  - `chaos.tasteam.kr/experiment-id`, `chaos.tasteam.kr/fi-series`, `chaos.tasteam.kr/vo`, `chaos.tasteam.kr/env`

---

## 10. 게임데이 운영 절차

> FI-04/05 runbook 구조(Pre-flight → 주입 → 관측 → 회복 → 보고)를 그대로 계승.

1. **Pre-flight** — 대상 워크로드 Ready 확인, steady-state 메트릭 baseline 기록, kill switch 명령 준비
2. **가설 선언** — 시나리오 카탈로그에서 1개 선택, 해당 VO의 합격 기준 사전 합의
3. **주입** — 모델 B로 `kubectl apply`, dashboard에서 실행 확인
4. **관측** — duration 동안 health loop + dashboard, 중단조건(7-2) 모니터링
5. **회복** — duration 종료 또는 수동 delete 후 steady-state 복귀 확인 (CA scale-down, 서킷 CLOSE 포함)
6. **판정 및 보고** — 사람이 합격/불합격 판정, FI-04 보고서 양식으로 증적 작성. **9장 측정 테이블의 Baseline/장애중/회복 3점을 채우고, SLO 환산 문장 + Grafana 시계열 캡처(주입 시점 마커 포함)를 첨부** → 포트폴리오 증적
7. **kill switch 상시 대기** — 7-2의 일괄 삭제 명령을 절차 최상단에 고정

---

## 11. 산출물 / 디렉토리 구조 제안

> 본 차수 산출물은 **설계 문서(본 문서)**. 아래는 후속 구현 시 권장 배치(설계안).

```
v3-k8s/
├── docs/fault-injection/
│   ├── fi-04/                         # 기존(인프라, AWS FIS)
│   ├── fi-05/                         # 기존(인프라, AWS FIS)
│   └── chaos-mesh/
│       ├── chaos-mesh-l2-design.md    # ← 본 문서
│       ├── fi-06-pod-eviction-runbook.md   # (후속) VO-1
│       ├── fi-07-network-delay-runbook.md
│       ├── fi-08-hpa-runbook.md            # (후속) VO-3
│       └── fi-09-circuit-breaker-runbook.md # (후속) VO-2
├── argocd/
│   ├── projects/
│   │   └── tasteam-chaos-project.yaml # (후속) 6-2 설계안
│   └── apps/
│       └── chaos-mesh-install.yaml    # (후속) Helm 설치 Application
└── manifests/chaos/                   # (후속) 실험 CR 카탈로그(미동기화)
    ├── fi-06-pod-kill.yaml
    ├── fi-07-network-delay.yaml
    ├── fi-08-cpu-stress.yaml
    └── fi-09-external-partition.yaml
```

- 기존 `manifests/app/`(ArgoCD 동기화 대상)과 `manifests/chaos/`(카탈로그, 미동기화)를 **물리적으로 분리** — 6-3 모델 B 정합

---

## 12. 로드맵 — L2에서 L3로의 전이 조건

> 본 설계는 L3 전이를 막지 않도록 구조를 열어둠. 아래 충족 시 L3 착수.

| 전이 트리거 | L3에서 추가될 것 |
|---|---|
| 게임데이가 반복 패턴으로 안정화 | Chaos Mesh `Workflow`로 실험 시퀀스 자동화 |
| 가설 판정을 수동에서 자동으로 | `StatusCheck`/외부 probe로 steady-state 자동 pass/fail (VO별 합격기준을 probe로 코드화) |
| 회귀 방지 필요 | CI 파이프라인(`ci-templates/`)에 카오스 회귀 스테이지 편입 |
| 실험 이력 체계화 | 실험 CR을 GitOps 관리형(모델 A)으로 일부 전환 |

- **단일 스택 유지** — L3에서도 Litmus 신규 도입 없이 Chaos Mesh 내장 기능으로 충당 가능

---

## 13. 리스크 및 오픈 이슈

| # | 항목 | 영향 | 대응 |
|---|---|---|---|
| R1 | chaos-daemon privileged 권한 | 노드 보안 표면 확대 | RBAC 최소화, targetNamespace 제한 모드 검토 |
| R2 | AppProject 화이트리스트 미반영 | 카오스 CR 동기화 거부 | 6-2 `tasteam-chaos` 프로젝트 신설 |
| R3 | Linkerd가 장애를 흡수 | 실험 결과 해석 왜곡 | 8장 — 가설에 메시 회복력 명시 |
| R4 | NetworkPolicy와 partition 실험 간섭 | 결과 오염 | partition은 허용 경로 한정, 후속 차수로 |
| R5 | prod 게임데이 블래스트 반경 | 실사용자 영향 | 모델 B 통제·승인, mode 제한, kill switch |
| R6 | dashboard 외부 노출 | 무단 실험 주입 | 내부망 한정, RBAC |
| R7 | FI-08 부하 과다 시 pending pod | CA 미동작으로 미해소 → HPA 검증 오염 | 부하 강도를 노드 용량 내로 제한, pending 발생 시 즉시 중단 |
| R8 | FI-09 외부 egress 차단 범위 | 무관 트래픽 영향 | `externalTargets`를 의존성 IP/도메인으로 한정 |
| R9 | 누락 알림 보전 여부(VO-2) | 서킷 OPEN 중 알림 유실 가능성 | outbox/재시도 설계 확인 후 합격기준 확정 |
| R10 | **prod 단독 — 실사용자 직접 영향** | 모든 실험이 운영 트래픽에 노출 | `mode: one`, 저트래픽 시간대, 게임데이 승인·kill switch 필수(7장) |

### 13-1. 결정 대기(설계 확정을 위해 후속 합의 필요)

- [ ] Chaos Mesh 설치 모드 — 클러스터 전역 vs `targetNamespace: app-prod` 제한 (R1 연동)
- [ ] **prod 게임데이 승인 주체·절차** (prod 단독 수행 → 가장 중요)
- [ ] dashboard 노출 방식(포트포워딩 vs 내부 Ingress)
- [ ] FI-06~09 합격 기준의 정량 임계값 최종 확정(메트릭 baseline 측정 후)
- [ ] FI-09 — 서킷 OPEN 중 누락 알림의 보전 메커니즘(outbox/재시도) 동작 확인 (R9)

> 결정 완료: ~~CA 검증~~ → 제외(CA 미동작), ~~실험 환경~~ → prod 단독, ~~FI-08 부하 단계~~ → HPA만(노드 용량 내)

---

## 부록 A. 참고 — 기존 FI 시리즈와의 관계

| ID | 레이어 | 검증 목표 | 도구 | 상태 |
|---|---|---|---|---|
| FI-04 | 인프라(AZ 장애) | quorum·재스케줄 | AWS FIS | 완료 |
| FI-05 | 인프라(etcd 리더) | 리더 재선출 | AWS FIS | 완료 |
| **FI-06** | **앱(Pod 축출/재스케줄)** | **VO-1** | **Chaos Mesh** | **설계** |
| **FI-07** | **앱(서비스간 네트워크 지연)** | (Linkerd 회복력) | **Chaos Mesh** | **설계** |
| **FI-08** | **앱(HPA 스케일아웃)** | **VO-3** | **Chaos Mesh** | **설계** |
| **FI-09** | **앱(서킷브레이커)** | **VO-2** | **Chaos Mesh** | **설계** |
