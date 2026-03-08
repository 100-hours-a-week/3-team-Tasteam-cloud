# Loadtest Seed

`loadtest/seed/`는 부하테스트 실행 전에 필요한 더미 데이터 생성/주입 자산을 관리합니다.

## 구성

- `generate_dummy_seed_sql.py`: 대량 더미 데이터 + 부하테스트 계정/그룹 bootstrap SQL 생성기
- `config.example.json`: 기본 성능 시드 예제 설정
- `search_perf_test.json`: 검색 성능 테스트용 프리셋 설정
- `generated_dummy_seed.sql`: 기본 설정으로 생성해 둔 seed SQL
- `generated_dummy_cleanup.sql`: 기본 seed 정리용 SQL
- `search_perf_seed.sql`: 검색 성능 테스트용 생성 결과 예시
- `seed_restaurant_load.sql`: 음식점만 빠르게 대량 주입할 때 쓰는 단일 SQL

## 기본 사용

```bash
cd loadtest/seed
python3 generate_dummy_seed_sql.py \
  --cleanup-output generated_dummy_cleanup.sql
```

기본 출력 파일:
- `loadtest/seed/generated_dummy_seed.sql`
- `loadtest/seed/generated_dummy_cleanup.sql`

## 커스텀 설정 사용

```bash
cd loadtest/seed
python3 generate_dummy_seed_sql.py \
  --config config.example.json \
  --output out/seed.sql \
  --cleanup-output out/cleanup.sql
```

검색 성능용 프리셋:

```bash
cd loadtest/seed
python3 generate_dummy_seed_sql.py \
  --config search_perf_test.json \
  --output search_perf_seed.sql
```

## 설정 미리보기

```bash
cd loadtest/seed
python3 generate_dummy_seed_sql.py --print-config
```

## DB 주입 예시

```bash
cd loadtest/seed
psql "$DATABASE_URL" -f generated_dummy_seed.sql
psql "$DATABASE_URL" -f generated_dummy_cleanup.sql
```

음식점만 추가로 대량 확보할 때:

```bash
cd loadtest/seed
psql "$DATABASE_URL" -f seed_restaurant_load.sql
```

## 설정 포인트

- `counts`: 테이블별 삽입량
- `content`: 더미 문구, 이름, 주소, 좌표 분포, 그룹/검색 키워드 패턴
- `content.run_token`: 비워두면 자동 생성되며, 같은 배치의 정리 SQL 식별자 역할을 함
- `content.realistic_names`, `content.seoul_focused_coords`: 실서비스형 명칭과 서울권 좌표 분포를 켜는 옵션
- `tuning`: 메뉴 개수, 가격대, 리뷰 키워드 수 같은 생성 규칙

## 참고

- 생성 SQL에는 `test-user-001` 형식의 부하테스트 계정과 그룹/서브그룹/채팅방 bootstrap이 포함됩니다.
- `food_category`가 비어 있으면 `restaurant_food_category`는 자동 skip됩니다.
- `keyword`가 비어 있으면 `review_keyword`는 자동 skip됩니다.
