#!/bin/bash

# Blue-Green 무중단 배포 스크립트
# 다운타임 없이 8080 ↔ 8081 포트를 교대로 사용하여 배포

set -e  # 에러 발생 시 스크립트 중단

# ========================================
# 1. 환경 설정 및 인자 처리
# ========================================
JAR_PATH=$1
USERNAME="appuser"
BACKEND_DIR="/home/${USERNAME}/backend"
BLUE_PORT=8080
GREEN_PORT=8081
NOW=$(date +%Y%m%d_%H%M%S)
MAX_HEALTH_CHECK_WAIT=60  # Health Check 최대 대기 시간 (초)
CADDYFILE="/etc/caddy/Caddyfile"

if [ -z "$JAR_PATH" ]; then
    echo "Error: JAR 파일 경로가 인자로 전달되지 않았습니다."
    echo "사용법: $0 <JAR_PATH>"
    exit 1
fi

echo "======================================"
echo "  Blue-Green 무중단 배포 시작"
echo "======================================"
echo "배포 시각: $NOW"
echo "배포 사용자: $USERNAME"
echo "백엔드 디렉토리: $BACKEND_DIR"
echo "배포할 JAR: $JAR_PATH"
echo "Blue Port: $BLUE_PORT"
echo "Green Port: $GREEN_PORT"
echo ""

# ========================================
# 2. 현재 실행 중인 포트 감지
# ========================================
echo "[1/8] 현재 실행 중인 서버 확인 중..."

BLUE_PID=$(lsof -t -i :$BLUE_PORT 2>/dev/null || echo "")
GREEN_PID=$(lsof -t -i :$GREEN_PORT 2>/dev/null || echo "")

if [ ! -z "$BLUE_PID" ] && [ ! -z "$GREEN_PID" ]; then
    echo "✗ 오류: 두 포트 모두 실행 중입니다!"
    echo "  Blue Port ($BLUE_PORT): PID $BLUE_PID"
    echo "  Green Port ($GREEN_PORT): PID $GREEN_PID"
    echo "  하나의 포트만 실행되어야 합니다."
    exit 1
elif [ ! -z "$BLUE_PID" ]; then
    CURRENT_PORT=$BLUE_PORT
    CURRENT_PID=$BLUE_PID
    NEW_PORT=$GREEN_PORT
    CURRENT_COLOR="BLUE"
    NEW_COLOR="GREEN"
elif [ ! -z "$GREEN_PID" ]; then
    CURRENT_PORT=$GREEN_PORT
    CURRENT_PID=$GREEN_PID
    NEW_PORT=$BLUE_PORT
    CURRENT_COLOR="GREEN"
    NEW_COLOR="BLUE"
else
    echo "실행 중인 서버 없음"
    echo "→ 초기 배포: Blue Port ($BLUE_PORT) 사용"
    CURRENT_PORT=""
    CURRENT_PID=""
    NEW_PORT=$BLUE_PORT
    CURRENT_COLOR="없음"
    NEW_COLOR="BLUE"
fi

echo "✓ 현재 서버: $CURRENT_COLOR ($CURRENT_PORT)"
echo "✓ 새 서버: $NEW_COLOR ($NEW_PORT)"

# ========================================
# 3. 새 JAR 파일 준비
# ========================================
echo ""
echo "[2/8] 새 버전 준비 중..."
FINAL_JAR_NAME="backend-$NOW.jar"
cp $JAR_PATH $BACKEND_DIR/$FINAL_JAR_NAME

if [ ! -f "$BACKEND_DIR/$FINAL_JAR_NAME" ]; then
    echo "✗ JAR 파일 복사 실패"
    exit 1
fi

echo "✓ JAR 복사 완료: $FINAL_JAR_NAME"

# ========================================
# 4. 환경 변수 확인
# ========================================
echo ""
echo "[3/8] 환경 변수 확인 중..."
if [ -f "$BACKEND_DIR/.env" ]; then
    echo "✓ .env 파일 존재: $BACKEND_DIR/.env"
    echo ""
    echo "=== 환경 변수 내용 ==="
    cat "$BACKEND_DIR/.env"
    echo "======================"
else
    echo "⚠ Warning: .env 파일이 존재하지 않습니다."
    echo "  위치: $BACKEND_DIR/.env"
fi

# ========================================
# 5. 새 버전 시작 (새 포트)
# ========================================
echo ""
echo "[4/8] 새 서버($NEW_COLOR) 시작 중... (포트: $NEW_PORT)"
LOG_FILE="$BACKEND_DIR/app-$NOW.log"

cd $BACKEND_DIR
nohup java -jar \
  -Dspring.profiles.active=dev \
  -Dserver.port=$NEW_PORT \
  $FINAL_JAR_NAME \
  > $LOG_FILE 2>&1 &

NEW_PID=$!
cd - > /dev/null

echo "✓ 새 프로세스 시작 (PID: $NEW_PID, 포트: $NEW_PORT)"
echo "  로그 파일: $LOG_FILE"

# 최신 로그 심볼릭 링크 생성
ln -sf $LOG_FILE $BACKEND_DIR/app-latest.log

# ========================================
# 6. Health Check (새 서버)
# ========================================
echo ""
echo "[5/8] 새 서버($NEW_COLOR) Health Check 중..."
HEALTH_CHECK_URL="http://localhost:$NEW_PORT/actuator/health"
echo "Health Check URL: $HEALTH_CHECK_URL"
echo "최대 대기 시간: ${MAX_HEALTH_CHECK_WAIT}초"

HEALTH_CHECK_SUCCESS=false
ELAPSED=0

while [ $ELAPSED -lt $MAX_HEALTH_CHECK_WAIT ]; do
    # 프로세스가 살아있는지 확인
    if ! kill -0 $NEW_PID 2>/dev/null; then
        echo ""
        echo "✗ 새 서버 프로세스가 종료되었습니다 (PID: $NEW_PID)"
        echo ""
        echo "=== 최근 로그 (마지막 50줄) ==="
        tail -n 50 $LOG_FILE
        echo ""
        echo "=== 배포 실패 ==="
        echo "기존 서버($CURRENT_COLOR)는 계속 실행 중입니다."
        echo "전체 로그: $LOG_FILE"
        exit 1
    fi

    # Health Check 요청
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $HEALTH_CHECK_URL 2>/dev/null || echo "000")

    if [ "$HTTP_STATUS" = "200" ]; then
        HEALTH_CHECK_SUCCESS=true
        echo ""
        echo "✓ 새 서버($NEW_COLOR) Health Check 성공! (${ELAPSED}초 소요)"
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
    echo "=== 배포 실패: 새 서버 종료 중 ==="
    kill -15 $NEW_PID 2>/dev/null || true
    echo "기존 서버($CURRENT_COLOR)는 계속 실행 중입니다."
    echo "전체 로그: $LOG_FILE"
    exit 1
fi

# ========================================
# 7. Caddy 트래픽 전환
# ========================================
echo ""
echo "[6/8] Caddy 트래픽 전환 중..."

if [ -z "$CURRENT_PORT" ]; then
    echo "초기 배포 - Caddyfile 수정 불필요 (기본 포트 8080 사용)"
else
    echo "새 서버로 트래픽 전환: $CURRENT_PORT → $NEW_PORT"

    # Caddyfile 백업
    sudo cp $CADDYFILE ${CADDYFILE}.backup
    echo "✓ Caddyfile 백업 완료"

    # Caddyfile에서 포트 변경
    # reverse_proxy localhost:8080 → reverse_proxy localhost:8081 (또는 반대)
    sudo sed -i "s/localhost:${CURRENT_PORT}/localhost:${NEW_PORT}/g" $CADDYFILE

    echo "✓ Caddyfile 업데이트 완료 (포트: $CURRENT_PORT → $NEW_PORT)"

    # 변경 내용 확인
    echo ""
    echo "=== 변경된 Caddyfile 내용 ==="
    sudo grep "reverse_proxy" $CADDYFILE
    echo "============================="
    echo ""

    # Caddy 설정 검증
    echo "Caddy 설정 검증 중..."
    if ! sudo caddy validate --config $CADDYFILE 2>&1; then
        echo "✗ Caddy 설정 검증 실패!"
        echo "설정 복구 중..."

        sudo mv ${CADDYFILE}.backup $CADDYFILE
        echo "✓ 이전 설정으로 복구 완료"

        echo "새 서버 종료 중..."
        kill -15 $NEW_PID 2>/dev/null || true
        echo "기존 서버($CURRENT_COLOR)는 계속 실행 중입니다."
        exit 1
    fi

    echo "✓ Caddy 설정 검증 완료"

    # Caddy 리로드
    echo "Caddy 리로드 중..."
    if ! sudo caddy reload --config $CADDYFILE 2>&1; then
        echo "✗ Caddy 리로드 실패!"
        echo "설정 복구 중..."

        sudo mv ${CADDYFILE}.backup $CADDYFILE
        sudo caddy reload --config $CADDYFILE
        echo "✓ 이전 설정으로 복구 완료"

        echo "새 서버 종료 중..."
        kill -15 $NEW_PID 2>/dev/null || true
        echo "기존 서버($CURRENT_COLOR)는 계속 실행 중입니다."
        exit 1
    fi

    echo "✓ Caddy 리로드 완료 - 트래픽이 새 서버로 전환되었습니다!"

    # Caddy 백업 파일 삭제
    sudo rm ${CADDYFILE}.backup
fi

# ========================================
# 8. 기존 서버 종료
# ========================================
echo ""
echo "[7/8] 기존 서버($CURRENT_COLOR) 종료 중..."

if [ ! -z "$CURRENT_PID" ]; then
    echo "기존 서버 PID: $CURRENT_PID (포트: $CURRENT_PORT)"
    kill -15 $CURRENT_PID 2>/dev/null || true

    # Graceful Shutdown 대기 (최대 30초)
    for i in {1..30}; do
        if ! kill -0 $CURRENT_PID 2>/dev/null; then
            echo "✓ 기존 서버 종료 완료"
            break
        fi

        if [ $i -eq 30 ]; then
            echo "강제 종료 중..."
            kill -9 $CURRENT_PID 2>/dev/null || true
        fi

        sleep 1
    done
else
    echo "종료할 기존 서버 없음 (초기 배포)"
fi

# ========================================
# 9. 배포 이력 정리
# ========================================
echo ""
echo "[8/8] 배포 이력 정리 중..."

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

# ========================================
# 배포 완료
# ========================================
echo ""
echo "======================================"
echo "    무중단 배포 완료 ✓"
echo "======================================"
echo "배포 시각: $NOW"
echo "배포 방식: Blue-Green (무중단)"
echo ""
echo "이전 서버: $CURRENT_COLOR ($CURRENT_PORT) → 종료됨"
echo "현재 서버: $NEW_COLOR ($NEW_PORT) → 실행 중"
echo ""
echo "JAR 파일: $FINAL_JAR_NAME"
echo "프로세스: PID $NEW_PID"
echo "로그 파일: $LOG_FILE"
echo "최신 로그: $BACKEND_DIR/app-latest.log"
echo ""
echo "======================================"
echo "확인 명령어"
echo "======================================"
echo "Health Check: curl $HEALTH_CHECK_URL"
echo "외부 접속: curl https://tasteam.kr/api/actuator/health"
echo "실시간 로그: tail -f $BACKEND_DIR/app-latest.log"
echo "프로세스 확인: lsof -i :$NEW_PORT"
echo "Caddy 설정 확인: sudo cat $CADDYFILE | grep reverse_proxy"
echo "Caddy 검증: sudo caddy validate --config $CADDYFILE"
echo "Caddy 서비스: sudo systemctl status caddy"
echo "======================================"
