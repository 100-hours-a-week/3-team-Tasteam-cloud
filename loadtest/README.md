# Loadtest

저장소의 부하테스트 스크립트를 루트 `loadtest/` 아래에서 관리합니다.

## 구성

- `api-tests/`: k6 기반 API, 브레이크포인트, 스트레스, 스파이크, 복구 테스트
- `load-test/`: phase1, 장기 Soak, Cache/Kafka 비교, Locust 시나리오

## 시작 위치

```bash
cd loadtest/api-tests

# 또는
cd loadtest/load-test
```
