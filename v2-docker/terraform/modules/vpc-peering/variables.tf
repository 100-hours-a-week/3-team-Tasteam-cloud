variable "environment" {
  description = "Requester environment name (shared)"
  type        = string
}

variable "peer_environment" {
  description = "Accepter environment name (prod, stg, dev)"
  type        = string
}

variable "requester_vpc_id" {
  description = "Requester (shared) VPC ID"
  type        = string
}

variable "requester_cidr" {
  description = "Requester (shared) VPC CIDR block"
  type        = string
}

variable "requester_route_table_id" {
  description = "Requester (shared) private route table ID"
  type        = string
}

variable "accepter_vpc_id" {
  description = "Accepter (peer) VPC ID"
  type        = string
}

variable "accepter_cidr" {
  description = "Accepter (peer) VPC CIDR block"
  type        = string
}

variable "accepter_route_table_id" {
  description = "Accepter (peer) private route table ID"
  type        = string
}
