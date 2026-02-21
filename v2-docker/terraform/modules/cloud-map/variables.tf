variable "environment" {
  description = "환경 이름 (prod, dev, stg)"
  type        = string
}

variable "vpc_id" {
  description = "Cloud Map Private DNS Namespace를 연결할 VPC ID"
  type        = string
}

variable "service_name" {
  description = "Cloud Map 서비스 이름 (DNS 서브도메인으로 사용됨, e.g. spring)"
  type        = string
  default     = "spring"
}

variable "dns_ttl" {
  description = "Cloud Map DNS A 레코드 TTL (초) — 스케일 이벤트 반영 속도에 영향"
  type        = number
  default     = 10
}
