variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "migration-exp"
}

# ---------- EC2 (소스) ----------

variable "source_ami" {
  description = "Production EC2 AMI ID (소스 DB가 포함된 prod 스냅샷)"
  type        = string
  # prod AMI는 반드시 직접 지정 (terraform.tfvars)
}

variable "source_instance_type" {
  description = "소스 EC2 인스턴스 타입"
  type        = string
  default     = "c7i-flex.large"
}

variable "key_name" {
  description = "EC2 SSH key pair name"
  type        = string
  default     = "key-pair-mvp"
}

# ---------- EC2 (오케스트레이터) ----------

variable "orchestrator_instance_type" {
  description = "마이그레이션 오케스트레이터 EC2 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

# ---------- RDS (타겟) ----------

variable "db_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL 엔진 버전"
  type        = string
  default     = "17"
}

variable "db_name" {
  description = "RDS 초기 데이터베이스 이름"
  type        = string
  default     = "tasteam"
}

variable "db_username" {
  description = "RDS 마스터 유저명"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "RDS 마스터 비밀번호"
  type        = string
  sensitive   = true
}

variable "db_allocated_storage" {
  description = "RDS 할당 스토리지 (GB)"
  type        = number
  default     = 20
}
