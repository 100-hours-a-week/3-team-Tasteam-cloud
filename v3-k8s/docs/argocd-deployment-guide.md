# ArgoCD 배포 체계 구현 가이드

> **작성일**: 2026-03-15
> **기반 설계**: `v3-k8s/docs/05-kubeadm.md` 섹션 7
> **상태**: Spring Boot prod 파이프라인 구현 완료

---

## 1. 전체 배포 흐름

```
개발자 코드 push (backend-repo, main)
    │
    ▼
GitHub Actions CI
    ├── Docker 이미지 빌드
    ├── ECR 푸시 (태그: git SHA 7자리)
    └── cloud-repo cross-repo commit
         └── v3-k8s/manifests/app/overlays/prod/kustomization.yaml
             └── images[].newTag 업데이트
    │
    ▼
ArgoCD (클러스터 내)
    ├── cloud-repo Git 변경 감지 (3분 폴링)
    ├── prod: OutOfSync 표시 → 운영자 수동 Sync
    └── dev: 자동 동기화 (Auto Sync + Self Heal)
    │
    ▼
Kubernetes 클러스터
    ├── Rolling Update (maxSurge=1, maxUnavailable=0)
    ├── readinessProbe 통과 후 트래픽 수신
    └── progressDeadlineSeconds=120 → 실패 시 Degraded 알림
```

## 2. 디렉토리 구조

```
v3-k8s/
├── argocd/                          # ArgoCD 리소스
│   ├── apps/
│   │   ├── app-prod.yaml            # Application CR (수동 Sync)
│   │   ├── app-stg.yaml             # Application CR (수동 Sync)
│   │   └── app-dev.yaml             # Application CR (자동 Sync)
│   └── projects/
│       └── tasteam-project.yaml     # AppProject (소스/대상 제한)
│
├── manifests/
│   ├── app/
│   │   ├── base/                    # 공통 리소스 정의
│   │   │   ├── spring-boot/         # Spring Boot: Deployment, Service, HPA, PDB, ConfigMap
│   │   │   ├── fastapi/             # FastAPI: Deployment, Service, HPA, ConfigMap
│   │   │   ├── ingress-api.yaml     # API Ingress (/api, /ai)
│   │   │   ├── ingress-ws.yaml      # WebSocket Ingress (/ws, timeout 3600s)
│   │   │   ├── networkpolicy.yaml   # DNS허용 → 기본Deny → 서비스별 허용
│   │   │   └── kustomization.yaml
│   │   └── overlays/                # 환경별 오버라이드
│   │       ├── prod/kustomization.yaml
│   │       ├── stg/kustomization.yaml
│   │       └── dev/kustomization.yaml
│   └── helm/
│       └── values/
│           └── argocd.yaml          # ArgoCD Helm values (kubeadm 맞춤)
│
├── ci-templates/                    # backend-repo에 복사할 워크플로우
│   └── backend-cd-v3.yml
│
└── docs/
    ├── 05-kubeadm.md               # 아키텍처 설계 (Source of Truth)
    ├── runbook.md                   # 클러스터 구축 런북
    └── argocd-deployment-guide.md   # 이 문서
```

## 3. 설치 순서 (런북 Step 3-7 이후)

### 3.1 ArgoCD 설치 (Helm)

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

helm install argocd argo/argo-cd \
  -n argocd \
  -f v3-k8s/manifests/helm/values/argocd.yaml \
  --wait --timeout 10m
```

### 3.2 초기 비밀번호 확인

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### 3.3 AppProject + Application 등록

```bash
# 프로젝트 먼저
kubectl apply -f v3-k8s/argocd/projects/tasteam-project.yaml

# prod Application 등록
kubectl apply -f v3-k8s/argocd/apps/app-prod.yaml
```

### 3.4 Git 저장소 연결 확인

```bash
# ArgoCD CLI로 확인
argocd repo list

# 또는 UI에서 Settings → Repositories 확인
```

## 4. 환경별 동기화 정책

| 환경 | 동기화 | prune | selfHeal | 트리거 |
|------|--------|-------|----------|--------|
| prod | 수동 | - | - | 운영자가 ArgoCD UI에서 Sync 클릭 |
| stg | 수동 | - | - | 운영자 확인 후 수동 Sync |
| dev | 자동 | O | O | Git push → 즉시 반영 |

## 5. CI 워크플로우 (backend-repo)

### 5.1 필요한 GitHub Secrets

| Secret 이름 | 설명 |
|-------------|------|
| `AWS_DEPLOY_ROLE_ARN` | OIDC AssumeRole ARN (기존 v2와 동일) |
| `ECR_REGISTRY` | ECR 레지스트리 URL |
| `ECR_REPOSITORY_BACKEND` | ECR 리포지토리명 (tasteam-be) |
| `CLOUD_REPO_PAT` | cloud-repo에 push 권한이 있는 GitHub PAT |
| `DISCORD_WEBHOOK_URL` | Discord 알림용 (기존) |

### 5.2 워크플로우 설치

`v3-k8s/ci-templates/backend-cd-v3.yml`을 backend-repo의 `.github/workflows/`에 복사합니다.

### 5.3 cross-repo commit 동시성 처리

동일 파일을 여러 CI가 동시에 수정할 수 있으므로:
- push 실패 시 `git pull --rebase` 후 재시도 (최대 3회)
- Spring Boot와 FastAPI의 이미지 태그가 kustomization.yaml 내 별도 블록이므로 충돌 확률 낮음

## 6. 배포 실패 시 대응

### 6.1 자동 보호 (설계 문서 5.8 참조)

```
readinessProbe 실패 → Service에서 제외 → 트래픽 차단
maxUnavailable=0 → 기존 Pod 유지 → 서비스 무영향
progressDeadlineSeconds=120 초과 → Deployment Progressing=False
ArgoCD가 Degraded 상태로 표시
```

### 6.2 수동 롤백

```bash
# 긴급 롤백 (Git과 불일치 발생 — 이후 git revert 필요)
kubectl rollout undo deployment/spring-boot -n app-prod

# 권장: cloud-repo에서 git revert → ArgoCD Sync
cd cloud-repo
git revert HEAD
git push origin main
# ArgoCD에서 수동 Sync
```

## 7. 확장 계획

현재는 Spring Boot prod만 관통. 이후 확장:

1. **FastAPI prod**: 동일 패턴으로 ci-templates/ai-cd-v3.yml 작성
2. **stg/dev 환경**: overlays 이미 준비됨. Application CR만 등록하면 됨
3. **ArgoCD Notifications**: Discord webhook 연동으로 Sync 상태 알림
4. **Image Updater**: ArgoCD Image Updater 도입 시 cross-repo commit 불필요 (ECR 직접 감시)
