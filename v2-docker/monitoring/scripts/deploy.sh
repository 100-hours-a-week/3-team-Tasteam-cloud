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
  aws ssm get-parameters-by-path \
    --region "${AWS_REGION}" \
    --path "${SSM_PATH}" \
    --recursive \
    --with-decryption \
    --query "Parameters[*].[Name,Value]" \
    --output text 2>/dev/null | while IFS=$'\t' read -r name val; do
      [ -z "${name}" ] && continue
      key="${name##*/}"
      if [ -f "${ENV_FILE}" ] && grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "${ENV_FILE}"
      else
        echo "${key}=${val}" >> "${ENV_FILE}"
      fi
  done
fi

docker compose up -d
