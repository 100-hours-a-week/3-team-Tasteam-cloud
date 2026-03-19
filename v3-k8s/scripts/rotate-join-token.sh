#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="ap-northeast-2"
ENVIRONMENT="prod"

# 새 토큰 생성 (TTL 1시간)
# 기존 토큰은 삭제하지 않고 TTL 만료에 맡긴다 (경쟁 조건 방지)
NEW_TOKEN=$(kubeadm token create --ttl 1h)

aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name "/${ENVIRONMENT}/tasteam/k8s/join-token" \
  --value "$NEW_TOKEN" \
  --type SecureString \
  --overwrite

echo "[$(date)] Token rotated: ${NEW_TOKEN:0:6}..."
