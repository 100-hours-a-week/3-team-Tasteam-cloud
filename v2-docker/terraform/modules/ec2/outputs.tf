output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address"
  value       = aws_instance.this.private_ip
}

output "public_ip" {
  description = "Public IP address (null if not associated)"
  value       = aws_instance.this.public_ip
}

output "key_pair_name" {
  description = "AWS Key Pair name (manage_key_pair=false 시 null)"
  value       = one(aws_key_pair.this[*].key_name)
}

output "private_key_path" {
  description = "로컬에 저장된 private key 파일 경로 (manage_key_pair=false 시 null)"
  value       = one(local_sensitive_file.private_key[*].filename)
}
