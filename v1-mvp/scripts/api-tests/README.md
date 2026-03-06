# API Tests

k6 기반 API 테스트 스크립트 모음입니다.

## 📁 구조

```
api-tests/
├── smoke_test.js        # 스모크 테스트 (연결성 검증)
├── breakpoint_test.js   # 브레이크포인트 테스트 (한계점 탐색)
├── search_stress_test.js # 검색 기능 집중 부하 테스트
├── run-breakpoint.sh    # 브레이크포인트 테스트 실행 스크립트
├── run-search-stress.sh # 검색 부하 테스트 실행 스크립트
└── shared/
    ├── scenarios.js     # 공통 시나리오 및 헬퍼 함수
    └── test-utils.js    # 로그 및 메트릭 유틸리티
```

## 🔧 환경 변수

모든 환경변수는 기본값이 설정되어 있어 별도 설정 없이 바로 실행 가능합니다.
필요시에만 override하세요.

| 변수 | 설명 | 기본값 |
|-----|------|-------|
| `BASE_URL` | 테스트 대상 서버 URL | `https://stg.tasteam.kr` |
| `K6_PROMETHEUS_RW_SERVER_URL` | Prometheus Remote Write URL | `https://prom.tasteam.kr/api/v1/write` |
| `K6_PROMETHEUS_RW_USERNAME` | Prometheus Basic Auth 계정명 | `tasteam` |
| `K6_PROMETHEUS_RW_PASSWORD` | Prometheus Basic Auth 비밀번호 | (내장) |

> 🔒 **보안 주의**: 실제 계정명과 비밀번호는 보안상 `.envrc` 파일 등을 통해 환경변수로 직접 선언해야 안전하게 사용 가능합니다.
> `.envrc` 파일은 `.gitignore`에 포함되어 있습니다.

## 🧪 테스트 종류

### 스모크 테스트 (`smoke_test.js`)

배포 후 기본 연결성과 API 동작을 빠르게 검증합니다.

- **VU**: 1명
- **Duration**: 10초
- **용도**: CI/CD 파이프라인, 배포 직후 상태 확인

```bash
k6 run smoke_test.js
```

### 브레이크포인트 테스트 (`breakpoint_test.js`)

시스템이 SLO를 위반하기 시작하는 부하 수준을 탐색합니다.

- **시나리오**: 조회(80%) + 쓰기(20%) 동시 실행
- **부하**: 점진적 증가 (최대 조회 240 RPS, 쓰기 60 RPS)
- **Duration**: 8분

**SLO 기준:**

| 시나리오 | 임계치 |
|---------|--------|
| 조회 API | p95 < 1초 |
| 리뷰 작성 | p95 < 3초 |
| 에러율 | < 0.1% |

```bash
# 기본 실행 (Prometheus 출력 자동 활성화)
./run-breakpoint.sh

# DB 초기화 후 실행
./run-breakpoint.sh --reset-db

# Prometheus 출력 비활성화
./run-breakpoint.sh --no-prometheus
```

### 검색 부하 테스트 (`search_stress_test.js`)

검색 기능에 대한 집중적인 부하를 발생시킵니다.

- **시나리오**: 키워드 검색 (100%)
- **부하**: 최대 6000 VUs까지 단계적 증가
- **Duration**: 약 6분

```bash
# 실행
./run-search-stress.sh
```

## 📊 Prometheus / Grafana 연동

`run-breakpoint.sh` 실행 시 **기본적으로 Prometheus 출력이 활성화**됩니다.
네이티브 히스토그램도 스크립트 내에서 자동 활성화됩니다.

```bash
# 그냥 실행하면 됨 (모든 설정 내장)
./run-breakpoint.sh

# 다른 Prometheus 서버로 전송하고 싶다면:
K6_PROMETHEUS_RW_SERVER_URL="http://other-prom:9090/api/v1/write" ./run-breakpoint.sh
```

**네이티브 히스토그램 장점:**
- 저장 공간 최대 10배 절약
- 더 정확한 백분위수 계산
- 버킷 미리 정의 불필요

> Prometheus v3.8.0+ 및 Grafana 9.4+에서 정식 지원 (Stable)

### Test ID 및 메트릭

모든 테스트 실행 시 고유한 `Test ID`가 부여됩니다.

- **Tag**: `testid`
- **로그**: 실행 시작 시 콘솔에 출력 (예: `breakpoint-20250204-123456`)

**주요 커스텀 메트릭:**

- `request_success_count`: 전체 HTTP 요청 성공 수 (누적)
- `read_success_count`: 조회 시나리오 성공 수
- `write_success_count`: 쓰기 시나리오 성공 수
- `search_success_count`: 검색 시나리오 성공 수

## 🧩 공통 모듈 (`shared/scenarios.js`)

테스트 간 재사용되는 함수들을 제공합니다.

### 인증

- `login()` - 테스트 계정으로 로그인, 토큰 반환
- `joinGroup(token)` - 그룹 가입
- `getReviewKeywords(token)` - 리뷰 키워드 목록 조회

### 조회 API

- `getMainPage(token)` - 메인 페이지
- `getRestaurantList(token)` - 음식점 목록
- `getRestaurantDetail(token, id)` - 음식점 상세
- `getRestaurantReviews(token, id)` - 음식점 리뷰 목록
- `getGroupDetail(token, id)` - 그룹 상세
- `getGroupReviews(token, id)` - 그룹 리뷰 목록
- `getReviewDetail(token, id)` - 리뷰 상세
- `search(token, keyword)` - 통합 검색

### 쓰기 API

- `createReview(token, groupId, keywordIds)` - 리뷰 작성

### 복합 시나리오

- `executeReadScenario(state)` - 전체 조회 시나리오 (SLO: p95 < 1초)
- `executeWriteScenario(state)` - 전체 쓰기 시나리오 (SLO: p95 < 3초)

## 📋 테스트 계정 정보

테스트 스크립트는 아래 고정 테스트 데이터를 사용합니다:

| 항목 | 값 |
|-----|-----|
| 사용자 식별자 | `test-user-001` |
| 닉네임 | `스모크테스트계정1` |
| 테스트 그룹 ID | `2002` |
| 그룹 코드 | `LOCAL-1234` |
| 테스트 음식점 ID | `6001` |

> ⚠️ 테스트 실행 전 시드 데이터가 적재되어 있어야 합니다.

## 🔄 DB 초기화

테스트 데이터 오염을 방지하려면 DB 초기화 후 실행하세요:

```bash
# DB 초기화 후 브레이크포인트 테스트
./run-breakpoint.sh --reset-db

# 수동 초기화
../db-reset/reset-dev-db.sh
```
