```bash
#!/bin/bash
set -e

# ===== 설정 =====
NGINX_CONF="/etc/nginx/sites-available/default"  # 또는 실제 설정 파일 경로
BUILD_DIR="$HOME/frontend/build"
DEPLOY_DIR="/var/www/html"  # Nginx가 서빙하는 디렉토리

cd ~/frontend

echo "===== 프론트엔드 배포 시작 ====="

echo "[1/4] git pull"
git checkout main
git pull origin main

echo "[2/4] npm install & build"
npm install
npm run build

echo "[3/4] 빌드 파일 배포"
# 새 빌드 파일 복사
sudo rm -rf "$DEPLOY_DIR"/*
sudo cp -r "$BUILD_DIR"/* "$DEPLOY_DIR"/
sudo chown -R www-data:www-data "$DEPLOY_DIR"  # Nginx 유저 권한 설정

echo "[4/4] Nginx 재시작"
sudo nginx -t  # 설정 파일 문법 검사
if [ $? -eq 0 ]; then
    sudo systemctl reload nginx  # 또는 sudo systemctl restart nginx
    echo "Nginx 재시작 완료"
else
    echo "Nginx 설정 오류 발생"
    exit 1
fi

echo "===== 배포 완료 ====="
echo "배포 경로: $DEPLOY_DIR"
```