#!/bin/bash
set -e

PORT=8001

cd ~/ai

echo "===== AI 서버 배포 시작 ====="

echo "[1/4] git pull"
git checkout develop
git pull origin develop

echo "[2/4] 가상환경 및 패키지 설치"
python3 -m venv venv
source venv/bin/activate
pip install --no-cache-dir -r requirements.txt

echo "[3/4] 기존 프로세스 종료"
PID=$(lsof -ti :$PORT || true)
if [ -n "$PID" ]; then
    kill -15 "$PID"
    sleep 2
fi

echo "[4/4] FastAPI 서버 실행"
nohup python3 app.py > logs/ai.log 2>&1 &

echo "===== 배포 완료 ====="
echo "AI 서버 실행 중 (port $PORT)"