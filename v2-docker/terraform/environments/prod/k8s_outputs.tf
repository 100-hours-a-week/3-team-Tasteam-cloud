output "k8s_api_nlb_dns_name" {
  description = "Internal kube-apiserver NLB DNS name"
  value       = aws_lb.k8s_apiserver_internal.dns_name
}

output "k8s_ingress_nlb_dns_name" {
  description = "Public ingress NLB DNS name"
  value       = aws_lb.k8s_ingress_public.dns_name
}

output "k8s_apiserver_tg_arn" {
  description = "Internal kube-apiserver target group ARN"
  value       = aws_lb_target_group.k8s_apiserver.arn
}

output "k8s_ingress_http_tg_arn" {
  description = "Public ingress HTTP target group ARN"
  value       = aws_lb_target_group.k8s_ingress_http.arn
}

output "k8s_ingress_https_tg_arn" {
  description = "Public ingress HTTPS target group ARN"
  value       = aws_lb_target_group.k8s_ingress_https.arn
}

output "k8s_backup_bucket_name" {
  description = "K8s etcd / Sealed Secrets 백업 S3 버킷 이름 (BACKUP_BUCKET 환경변수에 사용)"
  value       = aws_s3_bucket.k8s_backup.bucket
}

output "k8s_cp_2a_instance_id" {
  description = "Track A control-plane instance ID"
  value       = module.ec2_k8s_cp_2a.instance_id
}

output "k8s_worker_2b_instance_id" {
  description = "Track A worker 2b instance ID"
  value       = module.ec2_k8s_worker_2b.instance_id
}

output "k8s_worker_2c_instance_id" {
  description = "Track A worker 2c instance ID"
  value       = module.ec2_k8s_worker_2c.instance_id
}
