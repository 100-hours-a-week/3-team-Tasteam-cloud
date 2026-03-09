# Tasteam 비동기/이벤트드리븐 모니터링 설계

## 1) 목적
- Spring 애플리케이션 내 비동기 처리(`@Async`, `@TransactionalEventListener`, Outbox/Replay/Dispatch, MQ, WebSocket)를 한 화면에서 상태 판단 가능하게 한다.
- 장애를 `증상`(큐 적체/실패율/지연/스레드 포화) 기준으로 빠르게 식별한다.
- 알림/사용자이벤트/채팅 도메인별로 원인 추적이 가능하도록 공통 라벨(`environment`, `instance`, `topic`, `provider`, `result`)을 표준화한다.

## 2) 현재 이미 수집되는 핵심 메트릭 (코드 확인 기준)

### 2.1 WebSocket/채팅
- `ws_connections_active`
- `ws_connect_total`
- `ws_disconnect_total`
- `ws_disconnect_by_reason_total{reason=...}`
- `ws_heartbeat_timeout_total`
- `ws_reconnect_total`
- `ws_session_lifetime_seconds_*`

### 2.2 MQ 추적
- `mq_publish_count_total{topic,provider,result}`
- `mq_consume_count_total{topic,provider,result}`
- `mq_consume_latency_seconds_*{topic,provider}`

### 2.3 사용자 이벤트(Analytics)
- `analytics_user_activity_outbox_enqueue_total{result}`
- `analytics_user_activity_outbox_publish_total{result}`
- `analytics_user_activity_outbox_retry_total{result}`
- `analytics_user_activity_dispatch_enqueue_total{result,target}`
- `analytics_user_activity_dispatch_execute_total{result,target}`
- `analytics_user_activity_dispatch_retry_total{result,target}`
- `analytics_user_activity_dispatch_circuit_total{state,target}`

### 2.4 알림(채팅 알림)
- `notification_chat_created_total`
- `notification_chat_push_sent_total`
- `notification_chat_push_skipped_online_total`

### 2.5 Spring/인프라 공통
- `executor_active_threads{name}`
- `executor_queued_tasks{name}`
- `executor_completed_tasks_total{name}`
- `process_cpu_usage`, `system_cpu_usage`
- `jvm_threads_live_threads`, `jvm_memory_*`
- `hikaricp_connections_pending`, `hikaricp_connections_active`
- `redis_errors_count_total`, `redis_eval_latency_*`
- `up{job="spring|redis|postgres|node"}`

## 3) 구현 상태 점검 (2026-03-07 코드 기준)
아래 항목은 모두 현재 구현에서 Prometheus로 노출된다.

### 3.1 Notification Outbox 상태 게이지 (구현 완료)
- `notification_outbox_pending`
- `notification_outbox_published`
- `notification_outbox_failed`
- `notification_outbox_retrying`
- 라벨: `environment`, `instance`
- 수집 방식: `NotificationOutboxService.summarize()` 결과를 `Gauge`로 주기 갱신

### 3.2 Notification Consumer 품질 (구현 완료)
- `notification_consumer_dlq_total{result}`
- `notification_consumer_process_total{result}`
- `notification_consumer_process_latency_seconds_*`
- 라벨: `environment`, `instance`, `result`

### 3.3 Source/Dispatch Outbox 적체 게이지 (구현 완료)
- `analytics_user_activity_source_outbox_pending`
- `analytics_user_activity_source_outbox_failed`
- `analytics_user_activity_dispatch_outbox_pending{target}`
- `analytics_user_activity_dispatch_outbox_failed{target}`
- 라벨: `environment`, `instance`, `target`

### 3.4 Replay 배치 결과 (구현 완료)
- `analytics_user_activity_replay_processed_total{result}`
- `analytics_user_activity_replay_batch_duration_seconds_*`

### 3.5 Async Executor 포화 경보용 메트릭 (구현 완료)
- `executor_queue_utilization{executor}` = queued / queue_capacity
- `executor_rejected_tasks_total{executor}`

### 3.6 추가 계측 후보 (선택)
- `notification.outbox.oldest.pending.age` (pending 최대 체류 시간)
- `analytics.user-activity.dispatch.backlog.age` (dispatch backlog 최대 체류 시간)

## 4) 권장 알람 규칙
- MQ Consume Fail Rate 급증: `sum(rate(mq_consume_count_total{result="fail"}[5m])) > 0`
- MQ Consume Success Ratio 저하: 성공률 `< 0.95` 5분 지속
- Executor Queue 적체: `executor_queued_tasks{name=~"search_history|ai_analysis"} > 100` 10분
- WS Heartbeat Timeout Ratio: `(increase(ws_heartbeat_timeout_total[5m]) / increase(ws_disconnect_total[5m])) > 0.2`
- Notification Outbox Pending 증가: 15분 연속 증가
- Analytics Dispatch Circuit Open 이벤트 발생: `increase(analytics_user_activity_dispatch_circuit_total{state="open"}[5m]) > 0`

## 5) 대시보드 구성 원칙
- 1행: 서비스 상태 요약(Up/CPU/Thread/DB connection pending)
- 2행: Async Executor 포화/처리량
- 3행: MQ Publish/Consume 성공률, 지연
- 4행: Notification 파이프라인(생성/푸시/Outbox)
- 5행: User Activity Source/Dispatch/Replay
- 6행: WebSocket 이벤트 신호
- 7행: Redis/RDS/Node 상관관계

## 6) 운영 체크리스트
- 환경 라벨은 `environment=prod|stg|dev`로 통일 (`shared` 사용 지양)
- 모든 커스텀 메트릭에 `environment`, `instance` 라벨 포함
- 카운터는 `_total` 규약 준수
- 실패/스킵/성공은 `result` 라벨로 단일 차원화
- 대시보드 쿼리는 metric 미존재 시 `or vector(0)`로 안전 처리
