# ingress-nginx 제한 완화 변경 내역 (2026-03-25)

## 목적

`ingress-nginx-controller`를 통과하는 요청에서 헤더/바디 크기 관련 제한으로 인한 차단을 줄이기 위해, 인그레스 애노테이션과 컨트롤러 전역 설정을 함께 완화한다.

## 변경 파일

- `v3-k8s/manifests/app/base/ingress-api.yaml`
- `v3-k8s/manifests/app/base/ingress-ws.yaml`
- `v3-k8s/manifests/helm/values/ingress-nginx.yaml` (신규)

## 변경 상세

### 1) API Ingress (`ingress-api.yaml`)

- `nginx.ingress.kubernetes.io/proxy-body-size: "10m"` -> `"0"`
  - 요청 바디 크기 제한 해제
- `nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"` -> `"128k"`
  - 프록시 버퍼 크기 상향

### 2) WebSocket Ingress (`ingress-ws.yaml`)

- `nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"` -> `"86400"`
- `nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"` -> `"86400"`

### 3) Controller 전역 설정 (`ingress-nginx.yaml`)

다음 값을 `controller.config`로 추가/상향했다.

- `proxy-body-size: "0"`
- `client-header-buffer-size: "64k"`
- `large-client-header-buffers: "8 128k"`
- `enable-underscores-in-headers: "true"`
- `ignore-invalid-headers: "false"`
- `proxy-buffer-size: "128k"`
- `proxy-buffers-number: "16"`
- `proxy-busy-buffers-size: "256k"`

또한 기존 설치 파라미터를 values 파일로 통합했다.

- `controller.replicaCount: 2`
- `controller.service.type: NodePort`
- `controller.service.nodePorts.http: 30080`
- `controller.service.nodePorts.https: 30443`
- `controller.admissionWebhooks.enabled: true`

## 적용 방법

```bash
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  -f v3-k8s/manifests/helm/values/ingress-nginx.yaml
```

## 검증 방법

```bash
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=5m
kubectl get configmap -n ingress-nginx ingress-nginx-controller -o yaml \
  | rg "client-header-buffer-size|large-client-header-buffers|proxy-body-size|proxy-buffer-size"
```

## 남아있는 상위 제한(주의)

ingress-nginx를 완화해도 아래 계층에서 제한될 수 있다.

- Cloudflare 플랜/설정 기반 헤더/요청 제한
- L7 프록시 또는 WAF 정책 제한
- 백엔드 애플리케이션(Spring/FastAPI) 자체 요청 크기 제한

즉, 실제 최대 허용치는 체인에서 가장 작은 제한값을 따른다.
