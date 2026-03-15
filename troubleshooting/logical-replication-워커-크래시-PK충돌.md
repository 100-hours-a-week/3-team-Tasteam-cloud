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

---

# 2차 발생 — review_keyword PK 충돌 (3/14)

## 증상
- 1차 해결 후 갭을 +1000으로 줄여서 재실험
- 컷오버 후 k6 에러율이 ~30%로 급증, **5분간 지속**
- B(RDS) 앱 로그:
  ```
  [ERROR] duplicate key value violates unique constraint "review_keyword_pkey"
    Detail: Key (id)=(2303) already exists.
    SQL: insert into review_keyword (keyword_id,review_id) values (?,?)
  ```
- 에러율 30% = k6의 쓰기 비율(30%)과 정확히 일치 → **리뷰 쓰기 전량 실패, 검색은 정상**
- 복제 워커 크래시(1차)와 달리, **앱 레벨에서의 INSERT 실패**

## 1차와의 차이점

| | 1차 (3/12) | 2차 (3/14) |
|---|---|---|
| 충돌 테이블 | user_activity_source_outbox | review_keyword |
| 갭 설정 | +1000 (1회만, k6 여러 번) | +1000 (직전 설정, k6 1회) |
| 실패 주체 | 복제 워커 (무한 크래시 루프) | B 앱 (INSERT 실패 → 500 응답) |
| 원인 | k6 반복으로 갭 누적 소진 | setval~컷오버 사이 복제가 갭 잠식 |

## 근본 원인

**setval(Phase 3)과 컷오버(Phase 4-3) 사이에 k6가 A에 쓰기 → A에서 생성된 review_keyword가 B로 복제 → 갭 소진**

시간순:
1. **Phase 3**: `setval('review_keyword_id_seq', max(id) + 1000)` — 예: max=1300 → seq=2300
2. **Phase 4-2**: k6 시작 → A에 리뷰 요청 → A가 review_keyword INSERT (id: 1301, 1302, ...)
3. A의 review_keyword가 B로 **실시간 복제** → B에 id 1301~2300+ 유입
4. **Phase 4-3**: 컷오버 → B 앱이 직접 INSERT → 시퀀스 2301부터 → 이미 존재하는 id와 충돌

### 갭 소진 계산
- k6 설정: 30 VU, iter rate ~5.8/s, 쓰기 30% → ~1.7 리뷰/초 ≈ ~100건/분
- 리뷰 1건당 review_keyword 1건 생성 → review_keyword도 ~100건/분
- setval → 컷오버 사이 꾸물거린 시간: 10분+ → 1000건 갭 소진

## 해결 방향

### A안: setval을 컷오버 직전으로 이동
- Phase 순서 변경: k6 시작(4-2) → setval → 컷오버(4-3)
- setval~컷오버 사이를 수 초로 단축 → 갭 1000으로도 충분
- 장점: 갭 크기를 최소화하면서 안전

### B안: 갭을 충분히 키우기
- setval 시점은 그대로, 갭을 10000+ 이상
- 장점: 절차 변경 없음
- 단점: "적정 갭"에 대한 실증 불가

## 교훈
- 시퀀스 갭은 **"컷오버 순간 동시 쓰기량"이 아니라 "setval~컷오버 사이 A에서 복제되는 총량"** 기준
- 에러율이 k6 시나리오의 읽기/쓰기 비율과 정확히 일치하면, 쓰기 경로만 실패한 것

## 해결
- 시퀀스 갭 부여한 직후 컷오버 실행하니 문제 해결