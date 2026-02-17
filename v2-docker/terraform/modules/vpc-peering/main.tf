# ──────────────────────────────────────────────
# VPC Peering Connection
# ──────────────────────────────────────────────

resource "aws_vpc_peering_connection" "this" {
  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id
  auto_accept = true

  tags = {
    Name = "${var.environment}-pcx-${var.peer_environment}"
  }
}

# ──────────────────────────────────────────────
# Routes — requester → accepter, accepter → requester
# ──────────────────────────────────────────────

# shared(requester)의 private RTB → peer VPC CIDR
resource "aws_route" "requester_to_accepter" {
  route_table_id            = var.requester_route_table_id
  destination_cidr_block    = var.accepter_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

# peer(accepter)의 private RTB → shared VPC CIDR
resource "aws_route" "accepter_to_requester" {
  route_table_id            = var.accepter_route_table_id
  destination_cidr_block    = var.requester_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}
