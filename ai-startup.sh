```bash
#!/bin/bash
set -e

cd ~/ai-server

echo "===== AI 서버 배포 시작 ====="

echo "[1/4] git pull"
git checkout main
git pull origin main

echo "[2/4] 가상환경 및 패키지 설치"
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

echo "[3/4] 기존 프로세스 종료"
PID=$(lsof -ti :8000 || true)
if [ -n "$PID" ]; then
    kill -15 "$PID"
    sleep 2
fi

echo "[4/4] FastAPI 서버 실행"
nohup python main.py > logs/ai-server.log 2>&1 &

echo "===== 배포 완료 ====="
echo "AI 서버 실행 중 (port 8000)"
```