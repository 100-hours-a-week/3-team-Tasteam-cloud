variable "environment" {
  description = "환경 이름 (prod, dev, stg)"
  type        = string
}

variable "purpose" {
  description = "ASG 용도 — Name 태그에 사용 (e.g. spring)"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "instance_type" {
  description = "EC2 인스턴스 타입 (e.g. t3.small)"
  type        = string
}

variable "ami_id" {
  description = "AMI ID (e.g. data.aws_ami.docker_base.id)"
  type        = string
}

variable "subnet_ids" {
  description = "ASG 배치 서브넷 ID 목록 (vpc_zone_identifier)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "인스턴스에 연결할 보안 그룹 ID 목록"
  type        = list(string)
}

variable "min_size" {
  description = "ASG 최소 인스턴스 수"
  type        = number
  default     = 1
}

variable "desired_size" {
  description = "ASG 희망 인스턴스 수"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "ASG 최대 인스턴스 수"
  type        = number
  default     = 2
}

variable "app_port" {
  description = "애플리케이션 포트 (e.g. 8080)"
  type        = number
  default     = 8080
}

variable "health_check_grace_period" {
  description = "인스턴스 시작 후 헬스체크 대기 시간 (초)"
  type        = number
  default     = 300
}

variable "cpu_target_value" {
  description = "스케일링 정책 목표 CPU 사용률 (%)"
  type        = number
  default     = 70.0
}

variable "root_volume_size" {
  description = "루트 EBS 볼륨 크기 (GB)"
  type        = number
  default     = 20
}

variable "enable_lifecycle_hooks" {
  description = "true 시 LAUNCHING/TERMINATING lifecycle hook 생성 — 서비스 디스커버리 연동 시 필요"
  type        = bool
  default     = false
}

variable "lifecycle_hook_timeout" {
  description = "Lifecycle hook heartbeat timeout (초) — Lambda 처리 시간 고려해 설정"
  type        = number
  default     = 300
}

variable "key_name" {
  description = "외부 제공 EC2 key pair name (manage_key_pair=false 시 사용)"
  type        = string
  default     = null
}

variable "manage_key_pair" {
  description = "true 시 tls_private_key + aws_key_pair를 모듈 내에서 자동 생성"
  type        = bool
  default     = false
}

variable "private_key_output_dir" {
  description = "생성된 private key(.pem) 저장 디렉토리 절대 경로"
  type        = string
  default     = "~/.ssh"
}
