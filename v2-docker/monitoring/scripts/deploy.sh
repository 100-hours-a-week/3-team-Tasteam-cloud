#!/bin/bash
set -e

DEPLOY_DIR="/home/ubuntu/tasteam/monitoring"
ENV_FILE="${DEPLOY_DIR}/.env"
SSM_PATH="/shared/tasteam/monitoring"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"

cd "${DEPLOY_DIR}"

# SSM에서 모니터링 파라미터 fetch → .env에 병합
# - POSTGRES_DSN 등 SecureString 포함
if command -v aws >/dev/null 2>&1; then
  # SSM 파라미터를 임시 파일에 저장 후 .env에 병합
  # - grep -v + printf 방식: DSN 내 특수문자(!*$& 등)로 인한 sed 치환 오류 방지
  # - docker compose는 .env의 $를 변수 참조로 해석 → $$로 이스케이프
  tmp_ssm=$(mktemp)
  aws ssm get-parameters-by-path \
    --region "${AWS_REGION}" \
    --path "${SSM_PATH}" \
    --recursive \
    --with-decryption \
    --query "Parameters[*].[Name,Value]" \
    --output text 2>/dev/null > "${tmp_ssm}" || true

  while IFS=$'\t' read -r name val; do
      [ -z "${name}" ] && continue
      key="${name##*/}"
      val="${val//\$/\$\$}"
      # 기존 키 제거 후 새 값 추가 (sed/awk 특수문자 이슈 회피)
      if [ -f "${ENV_FILE}" ]; then
        grep -v "^${key}=" "${ENV_FILE}" > "${ENV_FILE}.tmp" || true
        mv "${ENV_FILE}.tmp" "${ENV_FILE}"
      fi
      printf '%s=%s\n' "${key}" "${val}" >> "${ENV_FILE}"
  done < "${tmp_ssm}"
  rm -f "${tmp_ssm}"
fi

# 바인드 마운트 데이터 디렉토리 생성 및 권한 설정
# - Prometheus: nobody (uid 65534), Loki: uid 10001, Grafana: uid 472
mkdir -p prometheus/data loki/data grafana/data
sudo chown -R 65534:65534 prometheus/data
sudo chown -R 10001:10001 loki/data
sudo chown -R 472:472     grafana/data

docker compose up -d
