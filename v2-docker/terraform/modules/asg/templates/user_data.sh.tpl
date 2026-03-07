#!/bin/bash
# ECR 로그인 → Docker pull → 컨테이너 실행
# - 실제 이미지 URI와 컨테이너 설정은 배포 파이프라인(CodeDeploy)에서 관리 예정
# - 이 스크립트는 인스턴스 초기 기동 시 최소한의 환경 설정만 수행

set -euo pipefail

# IMDSv2 토큰 발급
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

echo "[user_data] Instance $INSTANCE_ID started in ${environment} environment"
echo "[user_data] Region: ${aws_region}, App port: ${app_port}"

# Ensure SSM agent is available for Session Manager access.
if ! command -v amazon-ssm-agent >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y || true
    apt-get install -y amazon-ssm-agent || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y amazon-ssm-agent || true
  fi
fi

systemctl enable amazon-ssm-agent >/dev/null 2>&1 || true
systemctl restart amazon-ssm-agent >/dev/null 2>&1 || true
