# CD (Continuous Deployment) 가이드

| 항목 | 내용 |
|---|---|
| 문서 목적 | 3개 서비스(Backend, Frontend, AI)의 CD(지속적 배포) 파이프라인 구조와 배포 전략, 정책을 설명한다. |
| 작성 및 관리 | CloudTeam |
| 최종 수정일 | 2026.01.26 |
| CI 가이드 | [CI (Continuous Integration) 가이드](../CI/README.md) |

---

## 목차

- [1. CD 파이프라인 개요](#1-cd-파이프라인-개요)
- [2. 배포 방식: SCP 채택 배경](#2-배포-방식-scp-채택-배경)
- [3. 서비스별 배포 전략](#3-서비스별-배포-전략)
- [4. 환경 및 Secrets 관리](#4-환경-및-secrets-관리)

---

## 1. CD 파이프라인 개요

### 1.1 핵심 원칙

- **Push-to-Deploy**: `develop` 또는 `main` 브랜치에 `push`(merge)가 발생하면 자동으로 배포 워크플로우가 실행됩니다.
- **GitHub Actions 중심**: 모든 배포는 GitHub Actions를 통해서만 실행되며, 서버에 직접 접속하여 배포하는 행위는 금지됩니다.
- **환경 분리**: `develop` 브랜치는 **개발(Development) 서버**로, `main` 브랜치는 **운영(Production) 서버**로 배포됩니다.

### 1.2 전체 아키텍처

```mermaid
graph TD
    subgraph GitHub
        A[Push to develop] --> B[CD Workflow];
        C[Push to main] --> D[CD Workflow];
    end

    subgraph GitHub Actions
        B -- triggers --> E{Job 실행};
        D -- triggers --> E;
        E -- development env --> F[Build & Deploy];
        E -- production env --> G[Build & Deploy];
    end

    subgraph Servers
        F -- SCP --> H[개발 서버];
        G -- SCP --> I[운영 서버];
    end
```

### 1.3 서비스별 CD 워크플로우

| 서비스 | 워크플로우 파일 | 트리거 | 특징 |
|---|---|---|---|
| **Backend** | `ci-cd-full.yml` | `develop`, `main` push | CI/CD 통합 워크플로우 내에서 배포 Job 실행 |
| **Frontend** | `cd.yml` | `develop`, `main` push | GitHub Environments 기반 환경별 배포 |
| **AI** | `cd.yml` | `develop`, `main` push | GitHub Environments 기반 환경별 배포 |

---

## 2. 배포 방식: SCP

| 구분 | Git Pull 방식 | SCP 방식 (채택) |
|---|---|---|
| **실행 주체** | 배포 서버 | GitHub Actions Runner |
| **서버 권한** | GitHub 저장소 접근 권한 **필요** | GitHub 저장소 접근 권한 **불필요** |
| **프로세스** | 분산적 (서버마다 실행) | 중앙집중적 (Actions에서 통제) |

### SCP 방식 선택 이유

1.  **보안 강화 (가장 중요)**
    - 서버에 GitHub 접근용 SSH 키나 토큰을 보관할 필요가 없습니다.
    - 이는 **최소 권한 원칙**을 준수하며, 배포 서버가 침해되더라도 코드 저장소의 안전을 보장합니다.

2.  **중앙 통제 및 추적성**
    - 모든 배포는 GitHub Actions 워크플로우를 통해서만 실행되므로, 모든 배포 기록(성공, 실패, 실행자, 커밋)이 로그로 남습니다.
    - 배포 프로세스가 중앙에서 관리되어 통제 및 감사 추적이 용이합니다.

3.  **저장소 설정과 무관**
    - 향후 GitHub 저장소가 `Private`으로 전환되더라도 배포 방식의 변경이 전혀 필요 없습니다.


---

## 3. 서비스별 배포 전략

모든 서비스는 SCP를 통해 서버의 임시 디렉토리(`~/SERVICE/temp`)로 파일을 전송한 후, 각 서비스에 맞는 배포 스크립트를 실행하는 2단계 배포 방식을 사용합니다.

### 3.0 배포 전략 선택 배경

각 서비스의 특성에 따라 서로 다른 배포 전략을 채택했습니다:

| 서비스 | 배포 전략 | 선택 이유 |
|---|---|---|
| **Backend** | **무중단 배포** (Blue-Green) | 레드오션인 리뷰 서비스의 특성상 **고가용성(High Availability)**이 필수적입니다. 사용자가 언제든지 리뷰를 작성하고 조회할 수 있어야 하므로, 배포 중에도 서비스 중단이 발생하지 않아야 합니다. |
| **Frontend** | 중단 배포 (Stop-and-Start) | 정적 파일 배포 방식으로, 배포 시간이 매우 짧아(수 초 이내) 중단 배포로도 충분합니다. Caddy를 통한 빠른 파일 교체로 사용자 영향을 최소화합니다. |
| **AI** | 중단 배포 (Stop-and-Start) | 새벽 시간대에 배치 작업으로 실행되어 미리 DB에 값이 저장되는 특성상 배포가 서비스에 영향을 주지 않습니다. 따라서 무중단 배포의 복잡성이 필요하지 않습니다. |

### 3.1 Backend: 무중단 배포 (Blue-Green)

- **배포 방식**: Caddy 리버스 프록시를 이용한 Blue-Green 배포
- **배포 스크립트**: [`scripts/backend/blue-green-deploy.sh`](../../scripts/backend/blue-green-deploy.sh)
- **프로세스**:
    1.  `ci-cd-full.yml`의 `deploy` Job이 실행됩니다.
    2.  새로운 JAR 파일을 서버의 임시 폴더로 전송합니다.
    3.  `blue-green-deploy.sh` 스크립트가 현재 비활성(Green) 환경에 새 버전을 실행합니다.
    4.  헬스 체크 후, Caddy가 트래픽을 Green 환경으로 전환합니다. (무중단)
    5.  기존 Blue 환경은 Standby 상태가 됩니다.

```mermaid
graph LR
    Caddy -- routes traffic --> Blue(Port 8080<br>Active v1.0);
    Caddy -- standby --> Green(Port 8081<br>Standby);

    subgraph Deploy New Version
        direction LR
        Deployer -- deploys v1.1 --> Green;
    end

    Deployer -- health check --> Green;
    Green -- OK --> Caddy;
    Caddy -- switches traffic --> Green;
```

### 3.2 Frontend & AI: 임시 디렉토리를 이용한 안전한 파일 교체

- **배포 방식**: 임시 디렉토리(temp)를 활용한 2단계 파일 교체
- **프로세스**:
    1.  `cd.yml`의 `deploy` Job이 실행됩니다.
    2.  빌드된 산출물(FE: 정적 파일, AI: 소스코드)을 서버의 임시 폴더(`~/frontend/temp` 또는 `~/ai/temp`)로 전송합니다.
    3.  전송이 **완전히 성공**하면, SSH 명령을 통해 실제 서비스 디렉토리의 내용을 삭제하고 임시 폴더의 내용으로 교체합니다.
    4.  이 방식은 파일 전송 중 오류가 발생해도 기존 서비스에 영향을 주지 않는 장점이 있습니다.

---

## 4. 환경 및 Secrets 관리

### 4.1 Frontend & AI: GitHub Environments 활용

Frontend와 AI는 `GitHub Environments`를 통해 `develop`과 `main` 환경을 분리합니다.

- **설정 위치**: `Repository > Settings > Environments`
- **환경 매핑**:
    - `develop` 브랜치 → `development` 환경
    - `main` 브랜치 → `production` 환경
- **Secrets**: 각 환경에 `HOST`, `USERNAME`, `KEY`, `PORT` 등 서버 접속 정보를 **Environment secrets**로 설정합니다. 워크플로우는 배포 시점에 맞는 환경의 Secret을 자동으로 사용합니다.

### 4.2 Backend: Repository Secrets 활용

Backend는 CI/CD 통합 워크플로우의 구조적 특성상 Repository Secrets를 직접 사용합니다.

- **설정 위치**: `Repository > Settings > Secrets and variables > Actions`
- **Secrets**: `DEVELOP_HOST`, `PROD_HOST` 와 같이 Secret 이름에 환경을 명시하여 구분합니다.

### 4.3 공통 Secret

- `DISCORD_WEBHOOK_URL`: 모든 워크플로우에서 공통으로 사용하는 Discord 알림용 Secret이며, **Repository secrets**에 설정합니다.
