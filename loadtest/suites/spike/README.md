# Spike

짧은 시간에 트래픽이 급증하는 상황을 재현하는 스파이크 테스트입니다.

## 목적

- 갑작스러운 유입 증가 시 지연시간과 오류율이 어떻게 변하는지 확인합니다.
- 특정 기능이 순간 피크를 버틸 수 있는지 빠르게 검증할 때 사용합니다.

## 특성

- 실행 시간: 약 3분
- `SPIKE_TARGET=search|main|group|chat|write`
- 읽기/쓰기/채팅/검색 등 특정 기능별 스파이크를 분리할 수 있습니다.

## 전제조건

- 테스트 계정 로그인 가능
- `group`, `chat`, `write` 타깃은 그룹/채팅방 맥락이 준비되어야 합니다.

## 실행

```bash
cd loadtest/suites/spike
SPIKE_TARGET=search ./run-spike.sh --no-prometheus
```

옵션:

- `--reset-db`
- `--no-prometheus`
