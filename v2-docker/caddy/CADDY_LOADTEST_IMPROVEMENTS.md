# Caddy 부하테스트 점검 및 개선 정리

## 1) gzip(encode) 빼고 실험해야 하나?
결론: 네, 빼고 실험하는 게 맞습니다.

- 현재 앱 사이트 설정에서 `encode gzip zstd`가 켜져 있습니다. (`snippets/common.caddy:2`)
- 압축은 네트워크 사용량을 줄여 주지만 CPU를 더 사용합니다.
- 그래서 병목이 CPU인지 네트워크인지 분리하려면 `no-compress` 기준점이 필요합니다.

권장 비교군(동일 시나리오/동일 RPS):

1. `Baseline`: `encode` 제거
2. `gzip only`: `encode gzip`
3. `현재값`: `encode gzip zstd`

최종 운영값은 p95/p99 지연시간, 에러율, Caddy CPU, 백엔드 CPU를 같이 보고 결정합니다.

## 2) 현재 Caddyfile에서 먼저 손봐야 할 지점

### A. Rate limit이 부하테스트 결과를 왜곡할 가능성 (우선순위 높음)
- 위치: `snippets/common.caddy:23-44`
- `/api/*` 경로는 `500 req/s per client_ip` 제한이며, 특정 IP(`211.244.225.166`)만 예외입니다. (`:8-11`)
- 로드 제너레이터 IP가 예외 대상이 아니면 429가 발생해 실제 처리 한계보다 낮게 측정됩니다.

개선:
1. 테스트 기간엔 로드 제너레이터 IP를 예외에 추가
2. 또는 테스트용 브랜치에서 `rate_limit` 임시 완화/비활성화

### B. `max_conns_per_host` 고정값이 병목이 될 수 있음
- 위치: `snippets/common.caddy:51-54`, `:67-70`, `:75-78` (200), `:59-62` (WS 1000)
- 업스트림 용량보다 낮으면 Caddy에서 대기열이 생겨 p95/p99가 먼저 악화될 수 있습니다.

개선:
1. `200 -> 400 -> 800` 단계 실험
2. 업스트림 커넥션/스레드 풀과 함께 튜닝

### C. 업스트림 장애/지연 대응 설정이 약함
- 위치: `snippets/common.caddy:51-79`
- 현재는 `reverse_proxy`에 세부 타임아웃/재시도/헬스체크 정책이 거의 없습니다.

개선:
1. `dial_timeout`, `response_header_timeout`, `read_timeout` 등 타임아웃 명시
2. 다중 업스트림 운영 시 `health_uri`, `fail_duration`, `max_fails`, `lb_try_duration` 적용

### D. 액세스 로그 비용 분리 측정 필요
- 위치: `snippets/common.caddy:4-6`
- 고RPS 환경에서 JSON access log는 CPU/디스크 I/O 비용이 큽니다.

개선:
1. 실험군 하나는 로그 최소화(또는 비활성화)로 오버헤드 계수 확인
2. 운영 기준군(로그 ON)과 비교해 현실 성능도 같이 기록

## 3) 부하테스트 실행 체크리스트

1. 테스트 전 `rate_limit` 영향 제거(예외 IP 또는 임시 완화)
2. `encode` 3개 비교군(Baseline/gzip/gzip+zstd) 측정
3. `max_conns_per_host` 단계별 튜닝
4. 장애 주입(업스트림 지연/1개 인스턴스 다운)에서 타임아웃/복구 시간 측정
5. 결과 기록 항목 통일:
   - p50/p95/p99 latency
   - RPS/throughput
   - 4xx/5xx 비율
   - Caddy CPU/MEM, 업스트림 CPU/MEM
   - egress bytes(압축 효과 확인)

## 4) 포트폴리오에 쓰기 좋은 개선 항목

정량값은 실제 측정치로 교체해서 사용:

1. `encode` A/B 테스트로 트래픽/CPU 병목 분리, 운영 인코딩 정책 재정의
2. `rate_limit` 정책과 부하테스트 설계를 분리해 측정 신뢰도 개선
3. `max_conns_per_host` 튜닝으로 고부하 구간 p95/p99 안정화
4. 업스트림 타임아웃/헬스체크 적용으로 장애 상황 에러율 감소
5. 로그 오버헤드 계수화로 관측 가능성(Observability)과 성능의 균형 확보

예시 문장:

- "Caddy `encode`/커넥션 설정 A/B 테스트를 통해 병목 구간을 분리하고 p95 latency를 개선했다."
- "부하테스트 시 rate-limit 정책 영향을 제거해 측정 신뢰도를 높이고, 운영 정책과 성능을 함께 최적화했다."
