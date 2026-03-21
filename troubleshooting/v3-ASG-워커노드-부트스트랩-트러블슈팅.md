# ASG Worker 노드 부트스트랩 트러블슈팅 로그

- 날짜: 2026-03-19 ~ 2026-03-20
- 대상: Cluster Autoscaler 도입을 위한 ASG 워커 노드 전환 (Phase 1)
- 관련 문서: `docs/superpowers/specs/2026-03-19-cluster-autoscaler-design.md`

---

## 목차

1. [containerd config 디렉토리 미존재](#1-containerd-config-디렉토리-미존재)
2. [kubelet node-labels 제한 (k8s 1.34)](#2-kubelet-node-labels-제한-k8s-134)
3. [ECR Credential Provider 미설치](#3-ecr-credential-provider-미설치)
4. [kubelet serving certificate CSR 미승인](#4-kubelet-serving-certificate-csr-미승인)
5. [새 ASG 노드 전체 파드 반복 재시작 (미해결)](#5-새-asg-노드-전체-파드-반복-재시작-미해결)

---

## 1. containerd config 디렉토리 미존재

### 증상

- user_data 실행 중 스크립트가 line 53에서 중단
- `/var/log/k8s-bootstrap.log`:
  ```
  /var/lib/cloud/instance/scripts/part-001: line 53: /etc/containerd/config.toml: No such file or directory
  ```
- 노드가 클러스터에 join되지 않음

### 원인

- `apt-get install containerd`가 `/etc/containerd/` 디렉토리를 자동 생성하지 않음
- `containerd config default > /etc/containerd/config.toml` 실행 시 디렉토리가 없어서 실패
- `set -euo pipefail`로 인해 이후 스크립트 전체 중단

### 해결

- user_data에 `mkdir -p /etc/containerd` 추가 (containerd config 생성 직전)

---

## 2. kubelet node-labels 제한 (k8s 1.34)

### 증상

- 노드가 join 후 kubelet이 시작 실패, 무한 재시작
- `journalctl -xeu kubelet`:
  ```
  failed to validate kubelet flags: unknown 'kubernetes.io' or 'k8s.io' labels
  specified with --node-labels: [node-role.kubernetes.io/worker]
  --node-labels in the 'kubernetes.io' namespace must begin with an allowed prefix
  (kubelet.kubernetes.io, node.kubernetes.io)
  ```

### 원인

- k8s 1.24+에서 보안 강화: kubelet이 `kubernetes.io`/`k8s.io` 네임스페이스 레이블을 자체 설정하는 것 금지
- 워커 노드가 `node-role.kubernetes.io/control-plane` 등을 위장하는 것 방지 목적
- kubeadm JoinConfiguration의 `kubeletExtraArgs`에 `node-labels: "node-role.kubernetes.io/worker="` 가 있었음

### 허용되는 prefix

- `kubelet.kubernetes.io/*`
- `node.kubernetes.io/*`
- 기타 명시적 허용 목록 (`kubernetes.io/arch`, `kubernetes.io/hostname` 등)

### 해결

- JoinConfiguration에서 `node-labels` 항목 제거
- 노드 join 후 CP에서 수동으로 레이블 부여: `kubectl label node <name> node-role.kubernetes.io/worker=`

---

## 3. ECR Credential Provider 미설치

### 증상

- 노드가 Ready 상태이나 파드가 `ImagePullBackOff`
- ECR 프라이빗 레지스트리에서 이미지 pull 실패

### 원인

- ASG user_data에 ECR credential provider 바이너리 및 설정이 없었음
- 기존 워커 노드는 수동으로 설치했었음

### 해결

- user_data에 다음 추가:
  - `ecr-credential-provider` 바이너리 설치 (`/usr/local/bin/ecr-credential-provider/`)
  - `/etc/kubernetes/credential-provider.yaml` 생성
  - `/etc/default/kubelet`에 `--image-credential-provider-config`, `--image-credential-provider-bin-dir` 플래그 추가

---

## 4. kubelet serving certificate CSR 미승인

### 증상

- 노드는 Ready이나 `kubectl logs`, `kubectl exec` 실행 시 TLS 에러:
  ```
  Error from server: Get "https://10.11.152.67:10250/containerLogs/...":
  remote error: tls: internal error
  ```
- Linkerd proxy의 PostStartHook 실패 → CrashLoopBackOff

### 원인

- kubeadm v1.34 기본값 `serverTLSBootstrap: true`
  - kubelet이 자체 서명 인증서 대신 CSR을 API server에 제출하고 승인 대기
- CSR 자동 승인 컨트롤러(`kubelet-csr-approver`)가 아직 미설치 (Phase 4 예정)
- 100개 이상의 `kubernetes.io/kubelet-serving` CSR이 Pending 상태로 누적

### 영향 체인

```
CSR 미승인
  → kubelet serving cert 없음
    → API server → kubelet TLS 연결 실패
      → kubectl logs/exec 불가
      → linkerd-proxy가 identity service에서 인증서 발급 못 받음
        → PostStartHook 타임아웃 (120초)
          → 컨테이너 kill → CrashLoopBackOff
```

### 해결

- 임시: `kubectl get csr -o name | xargs kubectl certificate approve`
- 영구: Phase 4에서 `kubelet-csr-approver` (postfinance) 설치 예정

### 비고

- 기존 워커 노드(2b, 2c)는 `serverTLSBootstrap` 없이 설치되었거나 수동 승인됨

---

## 5. 새 ASG 노드 전체 파드 반복 재시작 (미해결)

### 증상

- 새 ASG 노드 2대의 **모든 파드**가 반복 재시작 (calico-node뿐 아니라 kube-proxy, fastapi 포함)
- 재시작 횟수 (23시간 기준):
  - kube-proxy: 247회 (기존 노드: 4일간 3~9회)
  - calico-node: 113회 (기존 노드: 4일간 3~4회)
  - fastapi: 188회 (linkerd PostStartHook 타임아웃 + 추가 재시작)
- 기존 워커 노드(2b, 2c)는 정상

### 영향 체인

```
kubelet이 killPod 실행 (원인 미확인)
  → 컨테이너 SIGTERM + 샌드박스 SIGKILL
    → PLEG: ContainerDied + SandboxChanged 감지
      → 새 샌드박스 생성 + 컨테이너 재시작
        → calico-node: BIRD 소켓 소실 → readiness probe 실패
        → kube-proxy: iptables 룰 갱신 불안정
        → DNS 조회 타임아웃 (CoreDNS 서비스 접근 불가)
          → linkerd-proxy가 identity/policy/dst 서비스 resolve 못함
            → PostStartHook 타임아웃 (120초) → 앱 파드 CrashLoopBackOff
```

### kubectl describe pod Events

- calico-node:
  ```
  Warning  Unhealthy  x109  Readiness probe failed: BIRD is not ready:
           unable to connect to BIRDv4 socket: connection refused
  Normal   Killing    x70   Stopping container calico-node
  ```
- kube-proxy:
  ```
  Normal   Killing  x208  Stopping container kube-proxy
  ```
- 두 파드 모두 에러 로그 없이 정상 기동 후 종료 반복
- kube-proxy exit code: 2 (기존 노드와 동일 — SIGTERM 시 정상 종료 코드)

### 소거된 원인 후보

| 후보 | 소거 근거 |
|------|----------|
| 커널 버전 차이 | 양쪽 동일: `6.17.0-1007-aws` |
| containerd 버전 차이 | 양쪽 동일: `1.7.28-0ubuntu1~24.04.2` |
| runc 버전 차이 | 양쪽 동일: `1.3.3-0ubuntu1~24.04.3` |
| containerd config.toml 차이 | grep 비교 결과 동일 (sandbox_image, SystemdCgroup, runtime_type 등) |
| kubelet config.yaml 차이 | 실질 동일 (`/run` vs `/var/run` 심링크 차이만 존재) |
| kubelet extra args 차이 | `/etc/default/kubelet` 동일 (ECR credential provider 설정) |
| 커널 OOM kill | `dmesg \| grep -i "oom\|killed process"` 결과 없음 |
| systemd-oomd | 양쪽 노드 모두 미설치 (`Unit systemd-oomd.service could not be found`) |
| 노드 리소스 부족 | MemoryPressure=False, DiskPressure=False, PIDPressure=False |
| kubelet 재시작 | `NRestarts=0`, uptime 20h+ |
| containerd 재시작 | `starting containerd` 1회만 (최초 기동) |
| Tigera operator 간섭 | operator 로그에 재시작 지시 없음, 3/16 이후 신규 로그 없음 |
| BIRD6/IPv6 문제 | `IP6=none`, `FELIX_IPV6SUPPORT=false` 설정됨. 소스 코드상 0 peers = ready |
| liveness probe 직접 kill | liveness는 `/liveness:9099` (BIRD 소켓과 별개). Events에 liveness 실패 없음 |
| calico-node 전용 문제 | kube-proxy도 동일 빈도(~11회/hr)로 재시작 → 노드 레벨 문제 |
| shim/pause OOM kill | `dmesg \| grep -iE "shim\|pause\|oom\|killed process"` 결과 없음 |
| eviction | kubelet v=4: `"Eviction manager: no resources are starved"` |

### 심층 분석 — 킬 체인 추적 (3/20)

#### 1단계: strace — 누가 SIGTERM을 보내는가

```bash
strace -p <kube-proxy PID> -f -e trace=signal,exit_group
```

- kube-proxy가 SIGTERM 수신 후 `exit_group(2)` 호출 (정상 종료)
- `si_pid=0`, `si_code=SI_USER` → 컨테이너 PID 네임스페이스 **외부**에서 `kill()` 시스콜로 전송

#### 2단계: ftrace — SIGTERM 발신자 특정

```bash
# 커널 ftrace signal_generate + sched_process_exec 활성화
echo 1 > /sys/kernel/debug/tracing/events/signal/signal_generate/enable
echo 1 > /sys/kernel/debug/tracing/events/sched/sched_process_exec/enable
```

- `runc` 프로세스가 `SIGTERM` 전송, 부모는 `containerd-shim`
- 킬 체인 확정:

```
kubelet → CRI StopContainer → containerd → containerd-shim → runc kill → SIGTERM → 컨테이너
```

#### 3단계: containerd 로그 — StopContainer 확인

```
StopContainer for "834dd857..." with timeout 30 (s)
Stop container "834dd857..." with signal terminated
```

- kubelet이 CRI API를 통해 **명시적으로** StopContainer 호출
- 이전 grep이 너무 좁아 StopContainer를 놓쳤었음

#### 4단계: kubelet v=4 — computePodActions & SandboxChanged

`/etc/default/kubelet`에 `--v=4` 추가 후 분석:

**kube-proxy 킬 시퀀스 (20:25:01~02):**

| 시각 | 이벤트 | 출처 |
|------|--------|------|
| 20:25:01.900 | `"Killing container with a grace period"` kube-proxy (grace=30) | kubelet |
| 20:25:02.001 | `StopPodSandbox for "72398baa..."` | containerd |
| 20:25:02.016 | sandbox exit_status:**137** (SIGKILL) | containerd |
| 20:25:02.045 | `shim disconnected` + `cleaning up after shim disconnected` | containerd |
| 20:25:02.377 | PLEG: kube-proxy `running→exited`, sandbox `running→exited` | kubelet |
| 20:25:02.383 | `"No ready sandbox for pod can be found. Need to start a new one"` | kubelet |
| 20:25:02.383 | `computePodActions: KillPod: true, CreateSandbox: true, Attempt: 247` | kubelet |
| 20:25:02.383 | `SandboxChanged: "Pod sandbox changed, it will be killed and re-created."` | kubelet |

**calico-node, fastapi도 동일 패턴 확인.**

#### 핵심 발견

1. **kubelet이 full killPod 실행**: 컨테이너 kill + 샌드박스 kill (단순 컨테이너 재시작이 아님)
2. **샌드박스(pause 컨테이너)가 죽음**: exit_status:137 → `StopPodSandbox`에 의한 SIGKILL
3. **`shim disconnected`는 원인이 아니라 결과**: `StopPodSandbox` 호출 후 shim이 종료되는 것
4. **OOM이 아님**: dmesg에 shim/pause 관련 OOM kill 기록 없음
5. **`computePodActions` 이전에 킬 발생**: `"Killing container"` 로그가 `computePodActions KillPod: true` 보다 **먼저** 출력됨 — `computePodActions`의 KillPod: true는 이미 죽은 샌드박스에 대한 **사후 반응**

```
"Killing container" (20:25:01.900) ← 트리거 불명 — computePodActions 외부 코드 경로
  → computePodActions: KillPod: false (20:25:02.067) ← 아직 이전 상태
    → PLEG: 컨테이너+샌드박스 둘 다 exited (20:25:02.377)
      → computePodActions: KillPod: true, SandboxChanged (20:25:02.383) ← 사후 반응
```

### 미해결 — 근본 원인

**`"Killing container"` 를 트리거하는 최초 결정이 무엇인가?**

- `computePodActions`가 아닌 다른 kubelet 코드 경로에서 killPod 실행
- 가능한 후보:
  - liveness/startup probe 실패 핸들러
  - `SyncTerminatingPod` (파드 종료 상태 전환)
  - `HandlePodCleanups` (orphan 파드 정리)
  - 동일 sync 사이클 내 `computePodActions KillPod: true` 로그가 grep 버퍼링으로 누락
- kubelet v=4 grep 필터가 트리거 시점의 로그를 놓치고 있음

### 현재 상태 (3/20)

- 근본 원인 조사 보류 — 폴트 인젝션 실험 우선 진행
- **새 ASG 노드 2대 drain 완료** (워크로드 퇴거, DaemonSet만 잔류):
  ```bash
  kubectl drain prod-ec2-k8s-worker-i-0db7553d87b56d922 --ignore-daemonsets --delete-emptydir-data --force
  kubectl drain prod-ec2-k8s-worker-i-0673215a6694f8760 --ignore-daemonsets --delete-emptydir-data --force
  ```
- 복구 방법: `kubectl uncordon <node-name>`
- kubelet `--v=4` 디버그 모드 활성 상태 (i-0db7553d87b56d922)

### 다음 조사 방향

1. **kubelet 전체 로그 파일 캡처**: `journalctl -u kubelet -f > /tmp/kubelet-full.log`, 킬 이벤트 직전 20줄 분석
2. **기존 노드 vs 새 노드 직접 비교**:
   - `systemctl cat kubelet` (systemd 서비스 + drop-in)
   - `cat /var/lib/kubelet/config.yaml` (full diff)
   - `ps aux | grep kubelet` (실제 커맨드 라인 인자)
3. 새 노드 cgroup 구조 확인 (cgroup v2 관련)
4. 인스턴스 타입/서브넷/SG 등 인프라 레벨 차이 점검