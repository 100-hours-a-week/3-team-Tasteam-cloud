variable "environment" {
  description = "환경 이름 (prod, dev, stg)"
  type        = string
}

variable "purpose" {
  description = "서비스 용도 — 리소스 이름에 사용 (e.g. spring)"
  type        = string
}

variable "asg_name" {
  description = "EventBridge Rule이 감청할 ASG 이름"
  type        = string
}

variable "cloud_map_service_id" {
  description = "Lambda가 register/deregister를 호출할 Cloud Map 서비스 ID"
  type        = string
}

variable "app_port" {
  description = "Cloud Map에 등록할 애플리케이션 포트"
  type        = number
  default     = 8080
}

variable "lambda_timeout" {
  description = "Lambda 타임아웃 (초) — lifecycle hook heartbeat timeout보다 짧아야 함"
  type        = number
  default     = 30
}
