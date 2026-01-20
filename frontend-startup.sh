#!/bin/bash
set -e

# ===== 설정 =====
CADDY_CONF="/etc/caddy/Caddyfile"  # Caddy 설정 파일 경로 (참고용)
BUILD_DIR="$HOME/frontend/build"
DEPLOY_DIR="/var/www/html"  # Caddy가 서빙하는 디렉토리

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
sudo chown -R caddy:caddy "$DEPLOY_DIR"  # Caddy 유저 권한 설정

echo "[4/4] Caddy 재시작"
sudo caddy validate --config "$CADDY_CONF"  # 설정 파일 문법 검사
if [ $? -eq 0 ]; then
    sudo systemctl reload caddy
    echo "Caddy 재시작 완료"
else
    echo "Caddy 설정 오류 발생"
    exit 1
fi

echo "===== 배포 완료 ====="
echo "배포 경로: $DEPLOY_DIR"