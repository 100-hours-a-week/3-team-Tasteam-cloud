# Tasteam PostgreSQL RDS 대시보드 메트릭 설명

대상 파일: `monitoring/rds-monito.json`

## 변수(필터) 의미
- `환경 (env)`: 인스턴스 이름 prefix 기준(`prod`, `stg`)으로 분리하는 용도(CloudWatch 인스턴스 필터에도 사용).
- `PG Environment (pg_environment)`: Prometheus 라벨 `environment` 값 필터(현재 예: `shared`).
- `Instance`: PostgreSQL exporter 대상 인스턴스(`prod-rds`, `stg-rds` 등).
- `Database (datname)`: PostgreSQL 데이터베이스 이름.
- `Lock table (mode)`: 락 모드 필터.

## General Counters
- `Version`: PostgreSQL 버전 정보.
- `Start Time`: PostgreSQL 프로세스 시작 시점(재기동 여부 확인).
- `Current fetch data`: `tup_fetched` 누적값 합계. 인덱스/테이블에서 읽어온 row 수 누적.
- `Current insert data`: `tup_inserted` 누적값 합계.
- `Current update data`: `tup_updated` 누적값 합계.
- `Max Connections`: PostgreSQL 설정 최대 접속 수(`max_connections`).
- `Average CPU Utilization`(CloudWatch): RDS CPU 평균 사용률(%).
- `Free Memory`(CloudWatch): RDS 여유 메모리(bytes).
- `Free Storage Space`(CloudWatch): RDS 남은 스토리지(bytes).

## Settings
- `Shared Buffers`: PostgreSQL 버퍼 캐시 크기.
- `Effective Cache`: 옵티마이저가 가정하는 OS+DB 캐시 크기.
- `Maintenance Work Mem`: VACUUM/CREATE INDEX 등 유지보수 작업 메모리.
- `Work Mem`: 정렬/해시 등 쿼리 연산별 메모리.
- `Max WAL Size`: 체크포인트 전 허용 WAL 최대 크기.
- `Random Page Cost`: 랜덤 I/O 비용 가중치(플래너 힌트).
- `Seq Page Cost`: 순차 I/O 비용 가중치.
- `Max Worker Processes`: 백그라운드 워커 최대 수.
- `Max Parallel Workers`: 병렬 작업 전체 워커 최대 수.

## Database Stats
- `Rows`: 아래 항목의 5분 기준 초당 변화율(irate) 합계.
  - fetched: 읽어온 row
  - returned: 반환한 row
  - inserted: 삽입 row
  - updated: 수정 row
  - deleted: 삭제 row
- `Number of active connections`:
  - `numbackends`: 현재 DB별 백엔드 연결 수
  - `max_connections`: 최대 연결 수(한도선)
- `Conflicts/Deadlocks`:
  - conflicts: 동시성 충돌 발생률
  - deadlocks: 데드락 발생률
- `Active sessions`: `state="active"` 세션 수.
- `QPS`: `commit/s + rollback/s` (트랜잭션 처리율).
- `Fetch data (SELECT)`: `tup_fetched` 누적 시계열.
- `Transactions`: commit/rollback 초당 처리율.
- `Update data`: `tup_updated` 누적 시계열.
- `Return data`: `tup_returned` 누적 시계열.
- `Insert data`: `tup_inserted` 누적 시계열.
- `Lock tables`: 락 모드별 lock 개수.
- `Cache Hit Rate`: `blks_hit / (blks_hit + blks_read)`.
- `Idle sessions`: idle 계열 세션 수(`idle`, `idle in transaction`, `idle in transaction (aborted)`).
- `Delete data`: `tup_deleted` 누적 시계열.
- `Temp File (Bytes)`: 임시 파일 사용량 증가율(irate).

## 해석 시 주의
- `tup_*` 계열은 대부분 누적 카운터이므로, 추세/부하 비교는 `irate`/`rate` 패널을 우선 참고.
- `Rows`, `QPS`, `Transactions`, `Conflicts/Deadlocks`, `Temp File`은 이미 변화율 기반이라 순간 부하 감지에 유리.
- `Cache Hit Rate`는 1(100%)에 가까울수록 메모리 캐시 효율이 좋음.
