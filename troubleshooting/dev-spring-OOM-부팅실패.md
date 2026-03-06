# dev 스프링 서버 OOM 부팅 실패

## 문제 상황
dev 환경에서 스프링 애플리케이션이 시작되지 않고 반복적으로 재시작됨.
컨테이너 상태가 `Up About a minute`로 계속 재시작되는 것을 확인.

### 에러 메시지
```
org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'chatStreamSubscriber': Invocation of init method failed
Caused by: java.lang.OutOfMemoryError: unable to create native thread: possibly out of memory or process/resource limits reached
```

### 발생 시점
- 2026-03-06
- v2 부하테스트용 더미 데이터 주입 이후

## 원인 분석

### 직접 원인
`ChatStreamSubscriber`가 `@PostConstruct`에서 모든 채팅방에 대해 Redis Stream 구독 스레드를 개별 생성하는 구조.
부하테스트 데이터로 채팅방이 5개 → 2,255개로 급증하면서, 스레드 2,255개를 동시에 생성하다 OOM 발생.

### 환경 요인
- 서버 RAM: 1.9GB (swap 없음)
- JVM 메모리 제한(`-Xmx`) 미설정
- 컨테이너 메모리 제한 미설정

### 데이터 확인
```
 date       | count
------------+-------
 2026-02-04 |     1
 2026-02-05 |     1
 2026-02-10 |     1
 2026-03-01 |     2
 2026-03-05 |  2250   ← 부하테스트 데이터
```

## 해결
부하테스트로 생성된 3월 5일자 채팅 데이터를 FK 순서대로 삭제 후 컨테이너 재시작하여 정상 부팅 확인.

```sql
BEGIN;
DELETE FROM chat_message WHERE chat_room_id IN (SELECT id FROM chat_room WHERE created_at::date = '2026-03-05');  -- 50,000건
DELETE FROM chat_room_member WHERE chat_room_id IN (SELECT id FROM chat_room WHERE created_at::date = '2026-03-05');  -- 7,500건
DELETE FROM chat_room WHERE created_at::date = '2026-03-05';  -- 2,250건
COMMIT;
```

## 근본 대책
`ChatStreamSubscriber`의 채팅방당 1스레드 구독 구조를 공유 스레드 풀 방식으로 개선 필요.
현재 구조에서는 채팅방 수가 늘어날 때마다 동일 문제가 재발할 수 있음.
