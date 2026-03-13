# Logical Replication Tablesync 실패 트러블슈팅

## 증상
- subscription(`migration_sub`) 생성 후 tablesync가 진행되지 않음
- `pg_subscription_rel`에서 모든 테이블이 `srsubstate = 'd'` (data copy) 상태로 멈춤
- B(RDS) 테이블 카운트 전부 0건
- A(publisher)에 `active = false`인 좀비 슬롯(`pg_*_sync_*`)이 계속 누적

## 오진 과정

### 1차: max_replication_slots 부족으로 판단
- A 로그에서 `all replication slots are in use` 에러 확인
- `max_replication_slots`를 10 → 20 → 60으로 증가 + PostgreSQL 재시작
- **결과**: 좀비 슬롯만 더 많이 쌓임. 근본 원인 아님

### 2차: 좀비 슬롯 정리
- `pg_drop_replication_slot()`으로 비활성 슬롯 정리
- subscription disable/enable 반복
- **결과**: 정리해도 즉시 좀비 재생성. 근본 원인 아님

### 3차: subscription drop 후 재생성
- subscription 삭제 → 슬롯 전부 정리 → subscription 재생성
- **결과**: 동일 증상 반복. 근본 원인 아님

## 근본 원인
- `replication_user`에 **SELECT 권한이 없었음**
- B(RDS) 로그에서 확인: `could not start initial contents copy for table "public.promotion": ERROR: permission denied for table promotion`
- tablesync worker가 COPY를 시도할 때 권한 부족으로 실패 → exit code 1 → 슬롯은 영구(permanent)라 정리 안 됨 → 재시도 → 또 실패 → 좀비 누적

### 왜 빠졌나
- 런북 Step 3-2에서 `replication_user` 생성 + GRANT SELECT 해야 했음
- 이미 유저가 존재해서 생성 단계를 건너뛰면서 GRANT도 같이 건너뜀

## 해결
```sql
-- A(publisher)에서 실행
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication_user;
```

## 근본 원인을 찾은 방법
- B(RDS) 로그는 계속 확인하고 있었으나, 최신 로그 파일은 슬롯 부족 에러로 도배되어 있어서 권한 에러를 발견하지 못함
- 한번 로테이션된 **이전 로그 파일**에서 구독 시작 직후의 전환점을 확인 → 최초 에러가 `permission denied`였음을 발견
- 에러가 누적되면 최신 로그는 2차 증상(슬롯 부족)으로 가득 차서 1차 원인(권한 부족)이 묻힘

## 교훈
- 에러 로그가 폭주할 때는 **최신 로그가 아니라 에러가 처음 발생한 시점의 로그**를 찾아야 함
- A(publisher) 로그만 보면 슬롯 부족 에러만 보여서 오진하기 쉬움 — B(subscriber) 로그도 반드시 확인
- 기존 유저 재사용 시에도 권한 상태를 반드시 확인할 것
