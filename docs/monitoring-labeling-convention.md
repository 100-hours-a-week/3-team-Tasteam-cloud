# 모니터링 레이블링 컨벤션

> 작성일: 2026-02-26
> 적용 범위: v2-docker 기준, Alloy → Prometheus / Loki 파이프라인 전체

---

## 1. 레이블 체계

모든 메트릭(Prometheus)과 로그(Loki)는 아래 4개 레이블을 공통으로 가진다.

| 레이블 | 의미 | 허용 값 | 선언 위치 |
|--------|------|---------|----------|
| `environment` | 배포 환경 | `prod`, `dev` | Alloy `external_labels` |
| `role` | EC2 역할 (인프라 단위) | `app`, `caddy`, `redis`, `monitoring` | Alloy `external_labels` |
| `job` | 수집 대상 서비스 / 익스포터 | 아래 2절 참고 | Alloy 설정 내 직접 선언 |
| `instance` | 개별 EC2 식별자 | EC2 호스트명 (`HOSTNAME` env var) | Alloy `external_labels` |

### 레이블 조합 예시

| 상황 | `environment` | `role` | `instance` |
|------|--------------|--------|------------|
| prod App EC2 #1 | `prod` | `app` | `ip-10-0-1-10` |
| prod App EC2 #2 (ASG 스케일아웃) | `prod` | `app` | `ip-10-0-1-11` |
| prod Caddy EC2 | `prod` | `caddy` | `ip-10-0-0-5` |
| dev Caddy EC2 | `dev` | `caddy` | `ip-10-1-0-5` |
| prod Redis EC2 | `prod` | `redis` | `ip-10-0-2-10` |
| prod Monitoring EC2 | `prod` | `monitoring` | `ip-10-0-3-10` |

> `environment + role`로 EC2 계열을 식별하고, `instance`로 개별 EC2를 드릴다운한다.
> 동일 `role`이 환경별로 존재하는 경우(예: caddy) `environment`가 반드시 선언되어야 한다.

---

## 2. `job` 레이블 허용 값

`job`은 "무엇을 수집하는가"를 나타낸다. EC2 역할(role)과는 독립적이다.

| `job` | 수집 대상 | 수집 방식 |
|-------|----------|----------|
| `spring` | Spring Boot Actuator 메트릭 | `prometheus.scrape` |
| `caddy` | Caddy HTTP 서버 메트릭 | `prometheus.scrape` |
| `redis` | Redis 메트릭 | `prometheus.exporter.redis` |
| `postgres` | PostgreSQL 메트릭 | `prometheus.exporter.postgres` |
| `node` | 호스트 OS 메트릭 (CPU·메모리·디스크·네트워크) | `prometheus.exporter.unix` |
| `cadvisor` | 컨테이너 리소스 메트릭 | `prometheus.exporter.cadvisor` |
| `prometheus` | Prometheus 자체 메트릭 | `prometheus.scrape` |
| `loki` | Loki 자체 메트릭 | `prometheus.scrape` |
| `grafana` | Grafana 자체 메트릭 | `prometheus.scrape` |

> Alloy exporter(`prometheus.exporter.*`)는 기본적으로 `job`을 자동 생성하지만,
> 해당 자동값은 컨벤션과 다를 수 있으므로 scrape 시 타겟 또는 `relabeling`으로 명시 재정의한다.

---

## 3. 선언 위치 규칙

### 3-1. Prometheus

```
prometheus.remote_write "default" {
  endpoint { url = "..." }
  external_labels = {
    environment = sys.env("ENVIRONMENT"),   # "prod" | "dev"
    role        = sys.env("ROLE"),          # "app" | "caddy" | "redis" | "monitoring"
    instance    = sys.env("HOSTNAME"),
  }
}
```

- `environment`, `role`, `instance` → `prometheus.remote_write.external_labels`에 선언
- `job` → 각 `prometheus.scrape` 블록의 타겟 인라인에 선언

```
prometheus.scrape "spring" {
  targets = [{ __address__ = "...", job = "spring" }]
  ...
}
```

> exporter 계열(`node`, `cadvisor`, `redis`, `postgres`)은 scrape 타겟 자동 생성 시
> `job` 레이블이 컨벤션과 다르게 설정될 수 있다.
> 이 경우 `prometheus.relabel` 또는 타겟 인라인으로 덮어쓴다.

### 3-2. Loki

```
loki.write "default" {
  endpoint { url = "..." }
  external_labels = {
    environment = sys.env("ENVIRONMENT"),
    role        = sys.env("ROLE"),
    instance    = sys.env("HOSTNAME"),
  }
}
```

- `environment`, `role`, `instance` → `loki.write.external_labels`에 선언
- `job` → `loki.process.stage.static_labels`에 선언

```
loki.process "labels" {
  stage.static_labels {
    values = { job = "spring" }   # 해당 로그 소스의 서비스명
  }
  forward_to = [loki.write.default.receiver]
}
```

---

## 4. 환경변수 주입 규칙

Alloy가 읽는 환경변수는 docker-compose `environment` 섹션으로 주입한다.

| 환경변수 | 값 | 비고 |
|----------|---|------|
| `ENVIRONMENT` | `prod` \| `dev` | 배포 환경 |
| `ROLE` | `app` \| `caddy` \| `redis` \| `monitoring` | EC2 역할 |
| `HOSTNAME` | EC2 호스트명 | 셸 기본 변수 그대로 사용 |

```yaml
# docker-compose.yml 예시
services:
  alloy:
    environment:
      - ENVIRONMENT=${ENVIRONMENT:-prod}
      - ROLE=caddy                          # EC2 역할은 하드코딩
      - HOSTNAME=${HOSTNAME}
```

> `ROLE`은 배포 대상이 고정되므로 docker-compose에 하드코딩한다.
> `ENVIRONMENT`는 배포 파이프라인에서 주입하고, 기본값은 `prod`로 둔다.

---

## 5. Grafana 쿼리 패턴

```promql
# prod App EC2 전체 CPU 사용률
rate(node_cpu_seconds_total{environment="prod", role="app", mode="idle"}[5m])

# prod에서 특정 인스턴스 드릴다운
node_memory_MemAvailable_bytes{environment="prod", role="app", instance="ip-10-0-1-10"}

# prod Spring 요청 수
http_server_requests_seconds_count{environment="prod", job="spring"}
```

```logql
# prod App EC2 Spring 로그
{environment="prod", role="app", job="spring"}

# dev Caddy 로그
{environment="dev", role="caddy", job="caddy"}

# prod 전체 로그 (역할 무관)
{environment="prod"}
```
