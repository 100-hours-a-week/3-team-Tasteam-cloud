# Load Test Scripts

1차(병목 탐색) + 2차(장기 Soak) + Cache/Kafka OFF/ON 비교를 위한 스크립트 모음입니다.

## 구성

- `phase1_test.js`: 1차 테스트 통합 스크립트 (suite 기반)
- `long_soak_test.js`: 2차 24h/48h 장기 Soak 스크립트
- `locustfile.py`: 사용자 여정 기반 Locust 시뮬레이터
- `run-phase1.sh`: 1차 실행 래퍼
- `run-phase1-off.sh`: 1차 Cache/Kafka OFF 전용 실행
- `run-phase1-on.sh`: 1차 Cache/Kafka ON 전용 실행
- `run-long-24h.sh`: 24h Soak 실행 래퍼
- `run-long-24h-off.sh`: 24h Soak Cache/Kafka OFF 전용 실행
- `run-long-24h-on.sh`: 24h Soak Cache/Kafka ON 전용 실행
- `run-long-48h.sh`: 48h Soak 실행 래퍼
- `run-long-48h-off.sh`: 48h Soak Cache/Kafka OFF 전용 실행
- `run-long-48h-on.sh`: 48h Soak Cache/Kafka ON 전용 실행
- `run-cache-compare.sh`: OFF/ON 연속 실행 + 비교 리포트 생성
- `templates/cache-kafka-compare-report.md`: 수동 작성용 리포트 템플릿

## 빠른 실행

```bash
cd v1-mvp/scripts/load-test

# 1차 병목 탐색 (full)
BASE_URL=https://dev.tasteam.kr ./run-phase1-off.sh --suite full

# 1차 mixed (ON)
BASE_URL=https://dev.tasteam.kr ./run-phase1-on.sh --suite mixed

# 1차 OFF/ON 비교 실행
BASE_URL=https://dev.tasteam.kr ./run-cache-compare.sh --suite mixed

# 2차 24h Soak (OFF / ON)
BASE_URL=https://dev.tasteam.kr ./run-long-24h-off.sh
BASE_URL=https://dev.tasteam.kr ./run-long-24h-on.sh

# 2차 48h Soak (OFF / ON)
BASE_URL=https://dev.tasteam.kr ./run-long-48h-off.sh
BASE_URL=https://dev.tasteam.kr ./run-long-48h-on.sh
```

## Suite 목록 (`run-phase1.sh --suite`)

- `smoke`
- `spike`
- `separated`
- `mixed`
- `breakpoint`
- `full` (기본)

## Locust 실행

```bash
cd v1-mvp/scripts/load-test
BASE_URL=https://dev.tasteam.kr USERS=1000 SPAWN_RATE=50 RUN_TIME=35m ./run-locust.sh
```

## 참고

- 30분 rolling 에러율, Redis hit ratio, Kafka lag는 k6 단독 계산보다 Grafana/Prometheus에서 `testid` 태그로 확인하는 것을 권장합니다.
- `phase1_test.js`는 필수 데이터(group/subgroup/chat-room) 미확보 시 즉시 중단하도록 되어 있습니다.
