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
