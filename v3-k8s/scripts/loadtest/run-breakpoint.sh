#!/bin/bash
set -e

# FI-04 breakpoint 테스트: k8s 환경 한계점 측정
# 사용법: ./run-breakpoint.sh [breakpoint|breakpoint_read|breakpoint_write] [--no-prometheus]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUITE="${1:-breakpoint}"
shift 2>/dev/null || true

export BASE_URL="${BASE_URL:-https://api.tasteam.kr}"
export K6_PROMETHEUS_RW_SERVER_URL="${K6_PROMETHEUS_RW_SERVER_URL:-https://prom-dev.tasteam.kr/api/v1/write}"
export K6_PROMETHEUS_RW_USERNAME="${K6_PROMETHEUS_RW_USERNAME:-tasteam}"
export K6_PROMETHEUS_RW_PASSWORD="${K6_PROMETHEUS_RW_PASSWORD:-tasteam-k6-metrics}"
export K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM="${K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM:-true}"

USE_PROMETHEUS=true
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-prometheus)
      USE_PROMETHEUS=false
      shift
      ;;
    *)
      echo "알 수 없는 옵션: $1"
      exit 1
      ;;
  esac
done

DATE_DIR="$(date +%Y%m%d)"
DATETIME="$(date +%Y%m%d-%H%M%S)"
TEST_ID="breakpoint-${SUITE}-${DATETIME}"
DASHBOARD_DIR="${SCRIPT_DIR}/dashboard/${DATE_DIR}"
DASHBOARD_FILE="${DASHBOARD_DIR}/breakpoint-${SUITE}-${DATETIME}.html"
mkdir -p "${DASHBOARD_DIR}"

if [[ "$USE_PROMETHEUS" == "true" ]]; then
  K6_OUTPUT_ARG="-o experimental-prometheus-rw"
else
  K6_OUTPUT_ARG=""
fi

echo ""
echo "== Breakpoint Test =="
echo "   suite=${SUITE}"
echo "   target=${BASE_URL}"
echo "   testid=${TEST_ID}"
echo "   dashboard=${DASHBOARD_FILE}"
echo ""

cd "${SCRIPT_DIR}"
K6_WEB_DASHBOARD=true \
K6_WEB_DASHBOARD_EXPORT="${DASHBOARD_FILE}" \
k6 run $K6_OUTPUT_ARG \
  --tag testid="$TEST_ID" \
  -e TEST_ID="$TEST_ID" \
  -e TEST_SUITE="$SUITE" \
  -e TEST_GROUP_ID="1" \
  -e TEST_GROUP_CODE="9999" \
  breakpoint-test.js

echo ""
echo "Breakpoint 테스트 완료"
echo ""
