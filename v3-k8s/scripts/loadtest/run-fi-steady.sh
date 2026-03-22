#!/bin/bash
set -e

# FI 장애 주입 중 일정 부하 유지 스크립트
# Fault Injection 전에 시작하고, 실험 완료+복구 후 Ctrl+C로 종료
#
# 사용법: ./run-fi-steady.sh [VUS] [DURATION]
#   VUS: 동시 사용자 수 (기본: 30)
#   DURATION: 부하 지속 시간 (기본: 30m)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VUS="${1:-30}"
DURATION="${2:-30m}"

export BASE_URL="https://api.tasteam.kr"
export K6_PROMETHEUS_RW_SERVER_URL="${K6_PROMETHEUS_RW_SERVER_URL:-https://prom-dev.tasteam.kr/api/v1/write}"
export K6_PROMETHEUS_RW_USERNAME="${K6_PROMETHEUS_RW_USERNAME:-tasteam}"
export K6_PROMETHEUS_RW_PASSWORD="${K6_PROMETHEUS_RW_PASSWORD:-tasteam-k6-metrics}"
export K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM="${K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM:-true}"

DATE_DIR="$(date +%Y%m%d)"
DATETIME="$(date +%Y%m%d-%H%M%S)"
TEST_ID="fi-steady-${VUS}vus-${DATETIME}"
DASHBOARD_DIR="${SCRIPT_DIR}/dashboard/${DATE_DIR}"
DASHBOARD_FILE="${DASHBOARD_DIR}/fi-steady-${VUS}vus-${DATETIME}.html"
mkdir -p "${DASHBOARD_DIR}"

echo ""
echo "== FI Steady Load =="
echo "   target=${BASE_URL}"
echo "   vus=${VUS}, duration=${DURATION}"
echo "   testid=${TEST_ID}"
echo "   dashboard=${DASHBOARD_FILE}"
echo ""

cd "${SCRIPT_DIR}"
K6_WEB_DASHBOARD=true \
K6_WEB_DASHBOARD_EXPORT="${DASHBOARD_FILE}" \
k6 run -o experimental-prometheus-rw \
  --tag testid="$TEST_ID" \
  -e TEST_ID="$TEST_ID" \
  -e TEST_SUITE="smoke" \
  -e CACHE_MODE="off" \
  -e TEST_GROUP_ID="1" \
  -e TEST_GROUP_CODE="9999" \
  --vus "$VUS" \
  --duration "$DURATION" \
  fi-steady-load.js
