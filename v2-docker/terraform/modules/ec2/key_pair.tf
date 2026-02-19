# ──────────────────────────────────────────────
# Key Pair — 조건부 자동 생성
# manage_key_pair = true 시에만 리소스 생성
# ──────────────────────────────────────────────

# RSA 4096 개인키 생성
resource "tls_private_key" "this" {
  count = var.manage_key_pair ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS Key Pair 등록
# - key_name: {env}-tasteam-{purpose} (글로벌 리소스 네이밍)
# - Name 태그: {env}-kp-{purpose}
resource "aws_key_pair" "this" {
  count = var.manage_key_pair ? 1 : 0

  key_name   = "${var.environment}-tasteam-${var.purpose}"
  public_key = tls_private_key.this[0].public_key_openssh

  tags = {
    Name = "${var.environment}-kp-${var.purpose}"
  }
}

# 개인키 로컬 파일 저장 (permission 0600)
resource "local_sensitive_file" "private_key" {
  count = var.manage_key_pair ? 1 : 0

  content         = tls_private_key.this[0].private_key_pem
  filename        = "${pathexpand(var.private_key_output_dir)}/${var.environment}-tasteam-${var.purpose}.pem"
  file_permission = "0600"
}
