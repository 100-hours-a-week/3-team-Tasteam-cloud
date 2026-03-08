# Loadtest

`loadtest/` 아래의 부하테스트 자산을 `shared/` 공통 모듈과 `suites/` 개별 시나리오 폴더로 재정리했습니다.

## 구조

- [`shared/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/shared): k6 공통 시나리오, 메트릭 유틸리티
- [`suites/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites): 실행 가능한 부하테스트 단위
- [`loadtest/.envrc`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/.envrc): 공통 환경변수 예시

## 어떤 테스트를 써야 하나

| 폴더 | 목적 | 대략 실행 시간 | 비고 |
|---|---|---:|---|
| [`suites/smoke/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites/smoke) | 배포 직후 연결성/기본 API 확인 | 10초 | 테스트 계정과 그룹 시드 필요 |
| [`suites/realistic/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites/realistic) | 실제 사용자 여정 기반 통합 부하 | 약 42분 | 기본 추천 시작점 |
| [`suites/breakpoint/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites/breakpoint) | SLO 위반이 시작되는 지점 탐색 | 약 5분 | 조회/쓰기 비율 80:20 |
| [`suites/search-stress/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites/search-stress) | 검색 API 집중 부하 | 약 6분 | 비로그인 실행 가능 |
| [`suites/stress/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites/stress) | read-heavy / write-heavy / search-only 지속 부하 | 약 20분 | `TEST_TYPE` 선택 |
| [`suites/spike/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites/spike) | 순간 급증 트래픽 대응 확인 | 약 3분 | `SPIKE_TARGET` 선택 |
| [`suites/recovery/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites/recovery) | 스파이크 후 회복력 관찰 | 약 16분 | 저부하 복구 구간 포함 |
| [`suites/soak/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites/soak) | realistic 여정 기반 24h/48h 장기 부하 | 24h / 48h | `SOAK_MODE`, `CACHE_MODE` 사용 |
| [`suites/phase1/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites/phase1) | 1차 병목 탐색 및 Cache/Kafka 비교 | suite별 상이 | 그룹/서브그룹/채팅방 필수 |
| [`suites/phase1-soak/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites/phase1-soak) | phase1 시나리오 기반 24h/48h 장기 Soak | 24h / 48h | Cache on/off 비교용 |
| [`suites/locust/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/suites/locust) | Locust 기반 사용자 여정 시뮬레이션 | 기본 35분 | k6가 아닌 Locust 사용 |

## 사용 규칙

- 각 폴더 안에는 실행 스크립트, 엔트리 테스트 스크립트, 해당 테스트 설명용 `README.md`만 둡니다.
- 공통 함수는 [`shared/`](/Users/devon.woo/Workspace/Tasteam/3-team-Tasteam-cloud/loadtest/shared)에서만 관리합니다.
- 새 테스트를 추가할 때도 `suites/<suite-name>/` 아래에 넣고, 반드시 폴더별 `README.md`를 함께 작성합니다.

## 예시

```bash
cd loadtest/suites/realistic
./run-realistic.sh --no-prometheus
```
