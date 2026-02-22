variable "environment" {
  description = "환경 이름 (prod, dev, stg)"
  type        = string
}

variable "instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t3.small"
}

variable "allocated_storage" {
  description = "gp3 스토리지 크기 (GB)"
  type        = number
  default     = 20
}

variable "engine_version" {
  description = "PostgreSQL 엔진 버전"
  type        = string
  default     = "17"
}

variable "db_name" {
  description = "초기 데이터베이스 이름"
  type        = string
  default     = "tasteam"
}

variable "username" {
  description = "마스터 유저 이름"
  type        = string
}

variable "subnet_ids" {
  description = "DB 서브넷 그룹에 포함할 Private 서브넷 ID 목록 (최소 2 AZ)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "RDS에 적용할 보안 그룹 ID 목록"
  type        = list(string)
}

variable "multi_az" {
  description = "Multi-AZ 배포 여부"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "삭제 시 최종 스냅샷 스킵 여부 (prod는 false 권장)"
  type        = bool
  default     = false
}
