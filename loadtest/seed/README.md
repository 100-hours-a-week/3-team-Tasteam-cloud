# Loadtest Seed

`loadtest/seed/`는 부하테스트 실행 전에 필요한 더미 데이터 생성/주입 자산을 관리합니다.

## 구성

- `generate_dummy_seed_sql.py`: 대량 더미 데이터 + 부하테스트 계정/그룹 bootstrap SQL 생성기
- `config.example.json`: 기본 성능 시드 예제 설정
- `search_perf_test.json`: 검색 성능 테스트용 프리셋 설정
- `cloud_verify_profile.json`: 현실적인 서울권 분포를 유지하면서 대용량 검증 데이터를 만드는 cloud_verify 프리셋
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

cloud verify용 프리셋:

```bash
cd loadtest/seed
python3 generate_dummy_seed_sql.py \
  --config cloud_verify_profile.json \
  --output ../results/generated-seed-20260308/cloud_verify_seed.sql \
  --cleanup-output ../results/generated-seed-20260308/cloud_verify_cleanup.sql
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
- `tuning.include_async_log_data`: `user_activity_*`, `notification_outbox`, `consumed_notification_event`, `message_queue_trace_log` 같은 비동기 로그성 테이블 생성 여부
- `tuning.async_log_scale_percent`: business 데이터 대비 몇 퍼센트 수준으로 비동기 로그성 데이터를 만들지 정하는 배율

## 참고

- 생성 SQL에는 `test-user-001` 형식의 부하테스트 계정과 그룹/서브그룹/채팅방 bootstrap이 포함됩니다.
- business 성격이 강한 `announcement`, `promotion*`, `report`, `push_notification_target`, `refresh_token`, `restaurant_schedule_override`, `image/domain_image`, `chat_message_file`도 함께 생성할 수 있습니다.
- `restaurant_ai_results`, `ai_restaurant_feature`, `restaurant_image`, `review_image`, `image_optimization_job`는 테이블 존재 여부를 확인한 뒤에만 삽입하도록 안전 가드가 들어가 있습니다.
- `food_category`가 비어 있으면 `restaurant_food_category`는 자동 skip됩니다.
- `keyword`가 비어 있으면 `review_keyword`는 자동 skip됩니다.
- `tuning.include_async_log_data=true`이면 `group_member`, `review`, `member_search_history`, `member_favorite_restaurant`, `notification` 건수를 바탕으로 `user_activity_event`, `user_activity_source_outbox`, `user_activity_dispatch_outbox`, `notification_outbox`, `consumed_notification_event`, `message_queue_trace_log`를 현실적인 비율로 함께 생성합니다.
- 비동기 로그성 데이터는 임의 고정 건수가 아니라 `group.joined`, `review.created`, `ui.search.executed`, `ui.favorite.updated`, `ui.restaurant.viewed`, `ui.page.viewed`, `ui.page.dwelled` 흐름과 알림 발행 흐름에 맞춰 파생 생성됩니다.
- 이미지 URL, `storage_key`, `device_id`, `fcm_token`, 딥링크 같은 랜덤성/캐시 민감 필드는 `run_token + 도메인 키` 기반 의사난수 해시로 생성해, 재현 가능성을 유지하면서도 URL/키 카디널리티를 충분히 확보합니다.
- `batch_execution`, `run_meta` 같은 운영 제어 테이블은 여전히 생성 대상에서 제외합니다.
- `realistic_names=true` 프리셋은 cleanup 시 이름 대신 `run_token`이 들어간 asset URL도 함께 사용해 대상 데이터를 식별합니다.
