# Rollback 가이드

## 개요

GitHub Artifact를 활용한 롤백 시스템입니다. Backend는 JAR 파일, Frontend는 빌드 파일을 Artifact에 저장하여 특정 버전으로 되돌릴 수 있습니다.

## 도입 배경

### 서비스 가용성 보장

리뷰 서비스는 레드오션 시장으로, 점심과 저녁 시간대의 가용성이 매우 중요합니다. 목표는 **99.9% 가용성** 확보입니다.

### 빠른 장애 대응 필요성

develop → main PR 과정에서 다음과 같은 검증을 수행합니다:

- **빌드 검증**: 애플리케이션 빌드 성공 여부 확인
- **테스트 실행**: 단위 테스트 및 통합 테스트 실행
- **E2E 테스트**: End-to-End 시나리오 검증
- **정적 분석**: 코드 품질 및 보안 취약점 검사
- **코드 리뷰**: 팀원 간 수동 코드 리뷰
- **스모크 테스트**: 운영 배포 전 핵심 기능 동작 확인
- **스파이크 부하 테스트**: 급격한 트래픽 증가 시 안정성 검증

현재는 staging 환경 대신 **같은 스펙의 개발 서버**에서 검증을 진행합니다.

하지만 이러한 검증에도 불구하고, 실제 사용자가 예상치 못한 방식으로 서비스를 이용할 때 에러가 발생할 수 있습니다. 이런 상황에서 **즉각적인 롤백**이 필요합니다.

### MVP 단계 인프라

현재 MVP 단계로 Docker, S3와 같은 별도 인프라가 없는 환경입니다. 따라서 GitHub Artifact를 활용한 경량화된 롤백 시스템을 구축했습니다.

## Backend Rollback

### 실행 방법

1. GitHub Actions → **Backend Rollback** 워크플로우 선택
2. **Run workflow** 클릭
3. 입력:
   - **environment**: `develop` 또는 `main`
   - **run_number**: 되돌릴 빌드 번호
4. 실행

### 동작 과정

```
Run Number 입력 → Artifact 다운로드 → 비활성 포트 배포 → 헬스체크 → Nginx 전환 → 이전 포트 종료
```

1. 입력받은 Run Number로 해당 빌드의 JAR Artifact 다운로드
2. 현재 실행 중인 포트 확인 (8080 또는 8081)
3. 비활성 포트에 롤백 JAR 배포 및 실행
4. 헬스체크 (60초, `/actuator/health`)
5. 성공 시:
   - Nginx 설정 변경으로 트래픽 전환
   - 이전 포트 애플리케이션 종료
6. 실패 시:
   - 롤백 버전 종료
   - 기존 버전 유지

### 백업

- 현재 버전: `/home/{user}/backend/backup-{timestamp}/`
- 롤백 실패 시 기존 버전 자동 유지

## Frontend Rollback

### 실행 방법

1. GitHub Actions → **Frontend Rollback** 워크플로우 선택
2. **Run workflow** 클릭
3. 입력:
   - **environment**: `develop` 또는 `main`
   - **run_number**: 되돌릴 빌드 번호
4. 실행

### 동작 과정

```
Run Number 입력 → Artifact 다운로드 → 현재 버전 백업 → 파일 교체
```

1. 입력받은 Run Number로 해당 빌드의 정적 파일 Artifact 다운로드
2. 현재 `/var/www/html` 내용을 백업 디렉토리로 복사
3. 웹 루트 디렉토리 비우고 롤백 버전 파일로 교체

### 백업

- 현재 버전: `/home/{user}/frontend/backup-{timestamp}/`
- 수동 복구:
  ```bash
  sudo rm -rf /var/www/html/*
  sudo cp -r /home/{user}/frontend/backup-{timestamp}/* /var/www/html/
  ```

## Run Number 확인

GitHub Actions 탭에서 확인:

- Backend: **Backend CI/CD - Full Pipeline** 워크플로우
- Frontend: **Frontend CD** 워크플로우

각 실행 항목의 `#숫자`가 Run Number입니다.

## 주의사항

- Artifact는 90일간 보관되므로 90일 이전 버전은 롤백 불가
- 환경별로 분리되어 있으므로 동일 환경의 Run Number만 사용 가능
- 롤백 결과는 Discord로 알림
