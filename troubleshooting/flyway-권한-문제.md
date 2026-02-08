# Flyway 마이그레이션 권한 오류 트러블슈팅

## 문제 상황

### 에러 메시지
```
org.postgresql.util.PSQLException: ERROR: must be owner of table group_auth_code
at org.flywaydb.core.internal.sqlscript.DefaultSqlScriptExecutor.executeStatement
...
Caused by: org.postgresql.util.PSQLException: ERROR: must be owner of table group_auth_code
```

### 발생 시점
- Flyway 마이그레이션 중 `ALTER TABLE` DDL 실행 시
- 스크립트: `V20260208__alter_group_auth_code_code_length.sql`

## 원인 분석

### 기존 권한 구조
```sql
-- 테이블 소유자: appuser
-- Flyway 유저: DML 권한만 보유 (SELECT, INSERT, UPDATE, DELETE)
```

### 문제점
PostgreSQL에서는 **테이블 소유자(OWNER)만 DDL(ALTER TABLE, DROP TABLE 등) 실행 가능**
- Flyway가 DML 권한은 있었지만 OWNER가 아니어서 스키마 변경 불가
- `GRANT ALL PRIVILEGES`를 해도 ALTER TABLE은 OWNER 권한 필요

### 권한 확인 명령어
```bash
# 테이블 소유자 확인
sudo -u postgres psql -d tasteam -c "
SELECT tablename, tableowner 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename = 'group_auth_code';
"

# Flyway 유저 권한 확인
sudo -u postgres psql -d tasteam -c "
SELECT privilege_type
FROM information_schema.table_privileges 
WHERE grantee = 'flyway' 
  AND table_name = 'group_auth_code';
"
```

## 해결 방법

### 올바른 권한 구조
- **flyway**: 테이블 소유자 (OWNER) → DDL 실행 가능
- **appuser**: DML 권한 보유 → 런타임 데이터 조작 가능

### 해결 단계

#### 1. 모든 테이블 소유자를 flyway로 변경
```bash
sudo -u postgres psql -d tasteam -c "
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' OWNER TO flyway;';
    END LOOP;
END \$\$;
"
```

#### 2. 시퀀스 소유자도 flyway로 변경
```bash
sudo -u postgres psql -d tasteam -c "
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT sequencename 
        FROM pg_sequences 
        WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ALTER SEQUENCE public.' || quote_ident(r.sequencename) || ' OWNER TO flyway;';
    END LOOP;
END \$\$;
"
```

#### 3. appuser에게 모든 테이블 DML 권한 부여
```bash
sudo -u postgres psql -d tasteam -c "
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
    LOOP
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.' || quote_ident(r.tablename) || ' TO appuser;';
    END LOOP;
END \$\$;
"
```

#### 4. 시퀀스 권한도 appuser에게 부여
```bash
sudo -u postgres psql -d tasteam -c "
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT sequencename 
        FROM pg_sequences 
        WHERE schemaname = 'public'
    LOOP
        EXECUTE 'GRANT USAGE, SELECT ON SEQUENCE public.' || quote_ident(r.sequencename) || ' TO appuser;';
    END LOOP;
END \$\$;
"
```

#### 5. 향후 생성될 객체에 대한 기본 권한 설정
```bash
# 테이블 기본 권한
sudo -u postgres psql -d tasteam -c "
ALTER DEFAULT PRIVILEGES FOR ROLE flyway IN SCHEMA public 
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appuser;
"

# 시퀀스 기본 권한
sudo -u postgres psql -d tasteam -c "
ALTER DEFAULT PRIVILEGES FOR ROLE flyway IN SCHEMA public 
GRANT USAGE, SELECT ON SEQUENCES TO appuser;
"
```

## 검증

### 권한 확인
```bash
# appuser의 테이블 권한 확인
sudo -u postgres psql -d tasteam -c "
SELECT 
    table_name,
    string_agg(privilege_type, ', ' ORDER BY privilege_type) as privileges
FROM information_schema.table_privileges 
WHERE grantee = 'appuser' 
  AND table_schema = 'public'
GROUP BY table_name
ORDER BY table_name;
"

# flyway의 소유권 확인
sudo -u postgres psql -d tasteam -c "
SELECT 
    tablename,
    tableowner
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY tablename;
"
```

### 기대 결과
```
✅ flyway: 모든 테이블의 OWNER (DDL 가능)
✅ appuser: 모든 테이블의 DML 권한 보유 (SELECT, INSERT, UPDATE, DELETE)
✅ Flyway 마이그레이션 성공
✅ 애플리케이션 정상 작동
```

## 핵심 교훈

### PostgreSQL 권한 체계
1. **OWNER 권한**: DDL(CREATE, ALTER, DROP) 실행 가능
2. **GRANT 권한**: DML(SELECT, INSERT, UPDATE, DELETE)만 가능
3. **OWNER가 아니면 GRANT ALL을 해도 ALTER TABLE 불가**

### 권장 구조
- **마이그레이션 전용 유저 (flyway)**: 테이블 OWNER
- **애플리케이션 유저 (appuser)**: DML 권한만 보유
- 보안 측면에서 역할 분리 (Separation of Concerns)

### 주의사항
- `ALTER DEFAULT PRIVILEGES` 설정으로 향후 생성되는 객체에도 자동 권한 부여
- 시퀀스(SEQUENCE) 권한도 함께 설정 필요 (SERIAL/IDENTITY 컬럼 사용 시)
- `postgres` 슈퍼유저로만 OWNER 변경 가능