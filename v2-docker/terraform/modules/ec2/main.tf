# ──────────────────────────────────────────────
# EC2 Instance
# ──────────────────────────────────────────────

resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  # manage_key_pair=true → key_pair.tf에서 생성한 키 참조
  # manage_key_pair=false → 외부 주입 key_name 또는 null
  key_name                    = var.manage_key_pair ? one(aws_key_pair.this[*].key_name) : var.key_name
  associate_public_ip_address = var.associate_public_ip_address

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.environment}-ec2-${var.purpose}"
  }
}
