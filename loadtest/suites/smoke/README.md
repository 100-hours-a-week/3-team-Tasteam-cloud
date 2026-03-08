# Smoke

배포 직후 가장 먼저 돌리는 짧은 연결성 확인 테스트입니다.

## 목적

- 테스트 계정 로그인, 그룹 가입, 주요 읽기/쓰기 API가 최소한으로 살아 있는지 확인합니다.
- CI/CD 직후나 운영 반영 직후 빠른 헬스체크 용도로 사용합니다.

## 특성

- 실행 시간: 10초
- 부하: 1 VU
- 그룹, 음식점, 리뷰 키워드 같은 시드 데이터가 있어야 의미 있게 동작합니다.

## 전제조건

- `POST /api/v1/test/auth/token` 동작
- 테스트 그룹 `2002 / LOCAL-1234` 유효
- 테스트 음식점 `6001` 유효

## 실행

```bash
cd loadtest/suites/smoke
./run-smoke.sh
```

직접 실행도 가능합니다.

```bash
cd loadtest/suites/smoke
BASE_URL=https://stg.tasteam.kr k6 run smoke_test.js
```
