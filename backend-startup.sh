#!/bin/bash
set -e

# ===== 설정 =====
APP_PORT="8080"
LOG_DIR="$HOME/be/logs"

cd ~/be

echo "===== 배포 시작 ====="

echo "[1/5] git pull"
git checkout develop
git pull origin develop

echo "[2/5] build"
./gradlew clean build -x test

echo "[3/5] kill current process"
PID=$(lsof -ti :"$APP_PORT" || true)

if [ -n "$PID" ]; then
  kill -15 "$PID"

  for i in {1..30}; do
    if lsof -ti :"$APP_PORT" >/dev/null 2>&1; then
      sleep 1
    else
      break
    fi
  done
else
  echo "실행 중인 프로세스 없음"
fi

echo "[4/5] run new process"
mkdir -p "$LOG_DIR"

nohup java -jar app-api/build/libs/*-SNAPSHOT.jar \
  --spring.profiles.active=dev \
  > "$LOG_DIR/backend.log" 2>&1 &
  
echo "[5/5] wait for port $APP_PORT"

for i in {1..60}; do
  if lsof -ti :"$APP_PORT" >/dev/null 2>&1; then
    echo "서버 정상 기동 (port $APP_PORT)"
    exit 0
  fi

  if (( i % 10 == 0 )); then
    echo "서버 기동 대기 중... (${i}초 경과)"
  fi
  sleep 1
done

echo "서버 기동 실패 (port $APP_PORT 열리지 않음)"
echo "로그 확인: $LOG_DIR/backend.log"
exit 1