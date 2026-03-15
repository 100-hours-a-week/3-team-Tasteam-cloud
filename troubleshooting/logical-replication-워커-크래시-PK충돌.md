# Logical Replication 워커 크래시 — PK 충돌 무한 루프

## 증상
- Cloudflare 오리진 전환(컷오버) 후 B(RDS)에 실시간 복제가 전혀 안 됨
- B 테이블 카운트 0건 (초기 복사 데이터만 존재)
- A에서 WAL lag가 계속 증가
- `pg_stat_subscription`에서 워커 PID 없음 (`active = false`)
- B(RDS) 로그에서 동일 에러 무한 반복:
  ```
  ERROR: duplicate key value violates unique constraint "user_activity_source_outbox_pkey"
  DETAIL: Key (id)=(3774) already exists.
  CONTEXT: processing remote data for replication origin "pg_16389" during message type "INSERT" for replication target relation "public.user_activity_source_outbox" in transaction 12345
  ```

## 오진 과정

### 1차: 네트워크/타임아웃 문제로 판단
- `wal_sender_timeout`(60s) / `wal_receiver_timeout`(30s) 설정 확인
- 부하가 크지 않았으므로 타임아웃이 원인일 가능성 낮음
- **결과**: 타임아웃 조정으로는 해결 안 됨. 근본 원인 아님

### 2차: at-least-once 재전송으로 판단
- "워커가 데이터를 적용했지만 `confirmed_flush_lsn` 보고 전에 크래시 → A가 같은 트랜잭션 재전송 → PK 충돌"로 추정
- **결과**: 재전송 자체는 맞지만, **왜 같은 PK 범위에 데이터가 이미 있었는지**를 설명 못 함

## 근본 원인
- **시퀀스 갭 고갈**

### 상세 메커니즘
1. 최초 실험에서 B의 시퀀스를 `max(id) + 1000`으로 설정 (갭 = 1000)
2. k6 부하 테스트를 **여러 차례 반복** 실행 (매회 ~10,000건 이상의 리뷰 + outbox 생성)
3. 시퀀스 setval은 **1회만** 실행 → 갭은 1000 고정
4. A에서 k6가 쓰기 요청을 계속 보내면서 A의 시퀀스가 진행
5. A의 시퀀스가 B의 `max(id) + 1000` 범위를 추월
6. 컷오버 후 B 앱이 B의 시퀀스로 새 row를 INSERT → A에서 복제되어 온 row와 PK 충돌
7. 복제 워커가 INSERT 실패 → 크래시 → 재시도 → 같은 PK에서 또 실패 → **무한 루프**

### 왜 무한 루프인가
- Logical Replication 워커는 트랜잭션을 **반드시 완수**하려고 함
- PK 충돌로 실패해도 해당 트랜잭션을 건너뛰지 않음 (데이터 정합성 보장)
- `confirmed_flush_lsn`이 갱신되지 않으므로 A는 계속 같은 WAL을 재전송
- subscription을 disable/enable해도 같은 지점에서 재시도 → 해결 안 됨
- **DROP SUBSCRIPTION만이** 슬롯과 LSN 위치를 완전히 제거

### 왜 빠졌나
- setval +1000은 단일 실험 기준으로 충분해 보였음
- k6를 반복 실행하면서 갭이 소진되는 시나리오를 고려하지 않음
- 시퀀스는 DELETE해도 감소하지 않음 → 데이터를 지워도 갭은 복구 안 됨

## 해결
```sql
-- 1. B(RDS): subscription 제거 (워커 크래시 루프 중단)
ALTER SUBSCRIPTION migration_sub DISABLE;
DROP SUBSCRIPTION migration_sub;

-- 2. A(EC2): 잔여 슬롯 정리
SELECT pg_drop_replication_slot('migration_sub');

-- 3. B(RDS): 시퀀스 갭을 +100000으로 재설정
SELECT setval('<seq_name>', (SELECT COALESCE(max(id), 0) FROM <table>) + 100000);
-- 전체 48개 시퀀스에 대해 실행

-- 4. subscription 재생성
CREATE SUBSCRIPTION migration_sub
  CONNECTION 'host=... dbname=tasteam user=replication_user password=...'
  PUBLICATION migration_pub;
```

## 근본 원인을 찾은 방법
- B(RDS) 로그에서 `duplicate key value violates unique constraint` 에러 확인
- 충돌 PK 값(id=3774)이 A의 시퀀스 진행 범위와 B의 갭 범위가 겹치는 구간에 위치
- `SELECT last_value FROM user_activity_source_outbox_id_seq;`로 양쪽 시퀀스 비교 → A가 B의 갭을 추월한 것 확인

## 갭 크기 재산정
- k6 실측: 리뷰 ~1,170건/분, 연쇄 INSERT 포함 시퀀스 소비 ~3,000/분
- 갭 1,000 → 1분 내 고갈
- **+100,000으로 변경** — 10분 run 3회 반복에도 여유 확보

## 교훈
- 시퀀스 갭은 **전체 실험 기간의 누적 쓰기량**을 고려해서 설정해야 함 (1000 → 100000)
- setval은 **컷오버 직전에** 실행해야 함 — 미리 하면 그 사이에 갭이 소진됨
- setval은 **B에서만** 실행할 것 — A에서도 실행하면 양쪽 시퀀스가 같아져서 갭 무효화
- k6 반복 실행 시 매번 setval을 다시 해야 하는 게 아니라, **실험 전체를 리셋**하고 처음부터 다시 해야 함 → 재실험 체크리스트 필요성
- 시퀀스는 DELETE로 감소하지 않음 — 데이터를 지워도 시퀀스는 전진만 함
