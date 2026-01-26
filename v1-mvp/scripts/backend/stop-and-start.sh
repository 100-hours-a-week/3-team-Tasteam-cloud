#!/bin/bash

# 중단 배포 스크립트 (Stop-and-Start Deployment)
# 다운타임 발생: 기존 서버를 중지하고 새 버전을 시작

set -e  # 에러 발생 시 스크립트 중단

# 1. 환경 설정 및 인자 처리
JAR_PATH=$1
USERNAME="appuser"
BACKEND_DIR="/home/${USERNAME}/backend"
APP_PORT=8080  # 고정 포트 사용
NOW=$(date +%Y%m%d_%H%M%S)
HEALTH_CHECK_URL="http://localhost:$APP_PORT/actuator/health"
MAX_HEALTH_CHECK_WAIT=60  # Health Check 최대 대기 시간 (초)

if [ -z "$JAR_PATH" ]; then
    echo "Error: JAR 파일 경로가 인자로 전달되지 않았습니다."
    echo "사용법: $0 <JAR_PATH>"
    exit 1
fi

echo "=== 중단 배포 시작 ($NOW) ==="
echo "배포 사용자: $USERNAME"
echo "백엔드 디렉토리: $BACKEND_DIR"
echo "배포할 JAR: $JAR_PATH"
echo "포트: $APP_PORT"

# 2. 기존 프로세스 중지
echo ""
echo "[1/5] 기존 애플리케이션 중지 중..."
OLD_PID=$(lsof -t -i :$APP_PORT 2>/dev/null)

if [ ! -z "$OLD_PID" ]; then
    echo "기존 프로세스 발견 (PID: $OLD_PID)"
    kill -15 $OLD_PID

    # Graceful Shutdown 대기 (최대 30초)
    for i in {1..30}
    do
        if ! kill -0 $OLD_PID 2>/dev/null; then
            echo "프로세스 종료 완료"
            break
        fi

        if [ $i -eq 30 ]; then
            echo "강제 종료 중..."
            kill -9 $OLD_PID 2>/dev/null
        fi

        sleep 1
    done
else
    echo "실행 중인 프로세스 없음"
fi

# 3. 새 JAR 복사
echo ""
echo "[2/5] 새 버전 준비 중..."
FINAL_JAR_NAME="backend-$NOW.jar"
cp $JAR_PATH $BACKEND_DIR/$FINAL_JAR_NAME

if [ ! -f "$BACKEND_DIR/$FINAL_JAR_NAME" ]; then
    echo "Error: JAR 파일 복사 실패"
    exit 1
fi

echo "JAR 복사 완료: $FINAL_JAR_NAME"

# 4. 환경 변수 파일 확인
echo ""
echo "[3/6] 환경 변수 확인 중..."
if [ -f "$BACKEND_DIR/.env" ]; then
    echo "✓ .env 파일 존재: $BACKEND_DIR/.env"
    echo "환경 변수 내용:"
    cat "$BACKEND_DIR/.env"
else
    echo "⚠ Warning: .env 파일이 존재하지 않습니다."
    echo "  위치: $BACKEND_DIR/.env"
    echo "  환경 변수가 필요한 경우 배포가 실패할 수 있습니다."
fi

# 5. 새 버전 시작
echo ""
echo "[4/6] 새 버전 시작 중..."
LOG_FILE="$BACKEND_DIR/app-$NOW.log"

cd $BACKEND_DIR
nohup java -jar \
  -Dspring.profiles.active=dev \
  -Dserver.port=$APP_PORT \
  $FINAL_JAR_NAME \
  > $LOG_FILE 2>&1 &

NEW_PID=$!
cd - > /dev/null

echo "새 프로세스 시작 (PID: $NEW_PID)"
echo "로그 파일: $LOG_FILE"

# 최신 로그 심볼릭 링크 생성
ln -sf $LOG_FILE $BACKEND_DIR/app-latest.log
echo "최신 로그 링크: $BACKEND_DIR/app-latest.log"

# 6. Health Check
echo ""
echo "[5/6] Health Check 시작..."
echo "Health Check URL: $HEALTH_CHECK_URL"
echo "최대 대기 시간: ${MAX_HEALTH_CHECK_WAIT}초"

HEALTH_CHECK_SUCCESS=false
ELAPSED=0

while [ $ELAPSED -lt $MAX_HEALTH_CHECK_WAIT ]; do
    # 프로세스가 살아있는지 확인
    if ! kill -0 $NEW_PID 2>/dev/null; then
        echo ""
        echo "✗ 프로세스가 종료되었습니다 (PID: $NEW_PID)"
        echo ""
        echo "=== 최근 로그 (마지막 50줄) ==="
        tail -n 50 $LOG_FILE
        echo ""
        echo "=== 배포 실패 ==="
        echo "전체 로그: $LOG_FILE"
        exit 1
    fi

    # Health Check 요청
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $HEALTH_CHECK_URL 2>/dev/null || echo "000")

    if [ "$HTTP_STATUS" = "200" ]; then
        HEALTH_CHECK_SUCCESS=true
        echo ""
        echo "✓ Health Check 성공! (${ELAPSED}초 소요)"
        break
    fi

    printf "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ "$HEALTH_CHECK_SUCCESS" = false ]; then
    echo ""
    echo "✗ Health Check 실패 (${MAX_HEALTH_CHECK_WAIT}초 타임아웃)"
    echo ""
    echo "=== 최근 로그 (마지막 100줄) ==="
    tail -n 100 $LOG_FILE
    echo ""
    echo "=== 배포 실패 ==="
    echo "프로세스는 실행 중이지만 Health Check에 응답하지 않습니다."
    echo "프로세스 PID: $NEW_PID"
    echo "전체 로그: $LOG_FILE"
    echo ""
    echo "수동 확인: curl $HEALTH_CHECK_URL"
    exit 1
fi

# 7. 배포 이력 정리
echo ""
echo "[6/6] 배포 이력 정리 중..."

# 최신 5개 JAR만 남기고 삭제
JAR_COUNT=$(ls -t $BACKEND_DIR/backend-*.jar 2>/dev/null | wc -l)
if [ $JAR_COUNT -gt 5 ]; then
    echo "이전 JAR 파일 정리 중... (${JAR_COUNT}개 중 5개만 유지)"
    ls -t $BACKEND_DIR/backend-*.jar | tail -n +6 | xargs rm -f 2>/dev/null
    echo "✓ $(($JAR_COUNT - 5))개 파일 삭제 완료"
fi

# 최신 5개 로그만 남기고 삭제
LOG_COUNT=$(ls -t $BACKEND_DIR/app-*.log 2>/dev/null | wc -l)
if [ $LOG_COUNT -gt 5 ]; then
    echo "이전 로그 파일 정리 중... (${LOG_COUNT}개 중 5개만 유지)"
    ls -t $BACKEND_DIR/app-*.log | tail -n +6 | xargs rm -f 2>/dev/null
    echo "✓ $(($LOG_COUNT - 5))개 로그 삭제 완료"
fi

# temp 폴더 정리
if [ -d "$BACKEND_DIR/temp" ]; then
    rm -f $BACKEND_DIR/temp/*.jar 2>/dev/null
fi

echo ""
echo "======================================"
echo "         배포 완료 ✓"
echo "======================================"
echo "배포 시각: $NOW"
echo "JAR 파일: $FINAL_JAR_NAME"
echo "프로세스: PID $NEW_PID"
echo "포트: $APP_PORT"
echo "로그 파일: $LOG_FILE"
echo "최신 로그: $BACKEND_DIR/app-latest.log"
echo ""
echo "Health Check: curl $HEALTH_CHECK_URL"
echo "로그 확인: tail -f $BACKEND_DIR/app-latest.log"
echo "======================================"

