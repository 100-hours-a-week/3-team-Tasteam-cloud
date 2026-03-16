# ──────────────────────────────────────────────
# K8s Track A/B — Prod VPC 확장 리소스
# 기존 v2 리소스는 main.tf에 유지하고,
# kubeadm 전용 리소스만 이 파일에 추가한다.
# ──────────────────────────────────────────────

locals {
  private_subnet_2a = module.vpc.private_subnet_ids[0]
  private_subnet_2c = module.vpc.private_subnet_ids[1]
  private_subnet_2b = module.vpc.private_subnet_ids[2]

  public_subnet_2a = module.vpc.public_subnet_ids[0]
  public_subnet_2c = module.vpc.public_subnet_ids[1]
  public_subnet_2b = module.vpc.public_subnet_ids[2]

  k8s_apiserver_targets = {
    cp_2a = module.ec2_k8s_cp_2a.instance_id
  }

  k8s_ingress_targets = {
    worker_2b = module.ec2_k8s_worker_2b.instance_id
    worker_2c = module.ec2_k8s_worker_2c.instance_id
  }
}

# ──────────────────────────────────────────────
# IAM — K8s Node Role / Profile
# ──────────────────────────────────────────────

resource "aws_iam_role" "prod_k8s_node" {
  name = "prod-k8s-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "prod_k8s_node_ssm_managed_instance_core" {
  role       = aws_iam_role.prod_k8s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "prod_k8s_node_ecr" {
  name = "ecr-pull"
  role = aws_iam_role.prod_k8s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "prod_k8s_node_ssm" {
  name = "ssm-read"
  role = aws_iam_role.prod_k8s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParametersByPath",
        "ssm:GetParameters",
        "ssm:GetParameter"
      ]
      Resource = [
        "arn:aws:ssm:*:*:parameter/${var.environment}/tasteam/backend",
        "arn:aws:ssm:*:*:parameter/${var.environment}/tasteam/backend/*",
        "arn:aws:ssm:*:*:parameter/${var.environment}/tasteam/fastapi",
        "arn:aws:ssm:*:*:parameter/${var.environment}/tasteam/fastapi/*",
        "arn:aws:ssm:*:*:parameter/${var.environment}/tasteam/monitoring",
        "arn:aws:ssm:*:*:parameter/${var.environment}/tasteam/monitoring/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "prod_k8s_node_kms" {
  name = "kms-decrypt"
  role = aws_iam_role.prod_k8s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "prod_k8s_node_s3" {
  name = "k8s-s3-access"
  role = aws_iam_role.prod_k8s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [
          aws_s3_bucket.uploads.arn,
          aws_s3_bucket.analytics.arn,
          aws_s3_bucket.k8s_backup.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.uploads.arn}/*",
          "${aws_s3_bucket.analytics.arn}/*",
          "${aws_s3_bucket.k8s_backup.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "prod_k8s_node" {
  name = "prod-k8s-node-instance-profile"
  role = aws_iam_role.prod_k8s_node.name
}

# ──────────────────────────────────────────────
# Security Groups — K8s Nodes / NLBs
# ──────────────────────────────────────────────

resource "aws_security_group" "k8s_control_plane" {
  name        = "prod-sg-k8s-control-plane"
  description = "Security group for kubeadm control-plane nodes"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "prod-sg-k8s-control-plane"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "k8s_worker" {
  name        = "prod-sg-k8s-worker"
  description = "Security group for kubeadm worker nodes"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "prod-sg-k8s-worker"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "k8s_apiserver_nlb" {
  name        = "prod-sg-k8s-apiserver-nlb"
  description = "Security group for internal kube-apiserver NLB"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "prod-sg-k8s-apiserver-nlb"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "k8s_ingress_nlb" {
  name        = "prod-sg-k8s-ingress-nlb"
  description = "Security group for public ingress NLB"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "prod-sg-k8s-ingress-nlb"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "k8s_control_plane_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k8s_control_plane.id
  description       = "Allow all outbound"
}

resource "aws_security_group_rule" "k8s_worker_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k8s_worker.id
  description       = "Allow all outbound"
}

resource "aws_security_group_rule" "k8s_apiserver_nlb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k8s_apiserver_nlb.id
  description       = "Allow all outbound"
}

resource "aws_security_group_rule" "k8s_ingress_nlb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k8s_ingress_nlb.id
  description       = "Allow all outbound"
}

resource "aws_security_group_rule" "k8s_apiserver_nlb_ingress_6443_from_vpc" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  security_group_id = aws_security_group.k8s_apiserver_nlb.id
  description       = "Kubernetes API from prod VPC"
}

resource "aws_security_group_rule" "k8s_ingress_nlb_ingress_80" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k8s_ingress_nlb.id
  description       = "Public HTTP ingress"
}

resource "aws_security_group_rule" "k8s_ingress_nlb_ingress_443" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k8s_ingress_nlb.id
  description       = "Public HTTPS ingress"
}

resource "aws_security_group_rule" "k8s_control_plane_ingress_6443_from_apiserver_nlb" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s_control_plane.id
  source_security_group_id = aws_security_group.k8s_apiserver_nlb.id
  description              = "Kubernetes API from internal NLB"
}

resource "aws_security_group_rule" "k8s_control_plane_ingress_6443_from_worker" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s_control_plane.id
  source_security_group_id = aws_security_group.k8s_worker.id
  description              = "Kubernetes API from worker nodes"
}

resource "aws_security_group_rule" "k8s_control_plane_ingress_2379_2380_from_self" {
  type                     = "ingress"
  from_port                = 2379
  to_port                  = 2380
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s_control_plane.id
  source_security_group_id = aws_security_group.k8s_control_plane.id
  description              = "etcd peer traffic"
}

resource "aws_security_group_rule" "k8s_control_plane_ingress_10250_from_self" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s_control_plane.id
  source_security_group_id = aws_security_group.k8s_control_plane.id
  description              = "kubelet from control-plane nodes"
}

resource "aws_security_group_rule" "k8s_control_plane_ingress_10250_from_worker" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s_control_plane.id
  source_security_group_id = aws_security_group.k8s_worker.id
  description              = "kubelet from worker nodes"
}

resource "aws_security_group_rule" "k8s_control_plane_ingress_10257_from_self" {
  type                     = "ingress"
  from_port                = 10257
  to_port                  = 10257
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s_control_plane.id
  source_security_group_id = aws_security_group.k8s_control_plane.id
  description              = "kube-controller-manager"
}

resource "aws_security_group_rule" "k8s_control_plane_ingress_10259_from_self" {
  type                     = "ingress"
  from_port                = 10259
  to_port                  = 10259
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s_control_plane.id
  source_security_group_id = aws_security_group.k8s_control_plane.id
  description              = "kube-scheduler"
}

resource "aws_security_group_rule" "k8s_control_plane_ingress_4789_from_self" {
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.k8s_control_plane.id
  source_security_group_id = aws_security_group.k8s_control_plane.id
  description              = "Overlay network from control-plane nodes"
}

resource "aws_security_group_rule" "k8s_control_plane_ingress_4789_from_worker" {
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.k8s_control_plane.id
  source_security_group_id = aws_security_group.k8s_worker.id
  description              = "Overlay network from worker nodes"
}

resource "aws_security_group_rule" "k8s_worker_ingress_30080_from_ingress_nlb" {
  type                     = "ingress"
  from_port                = 30080
  to_port                  = 30080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s_worker.id
  source_security_group_id = aws_security_group.k8s_ingress_nlb.id
  description              = "Ingress NodePort HTTP from public NLB"
}

resource "aws_security_group_rule" "k8s_worker_ingress_30443_from_ingress_nlb" {
  type                     = "ingress"
  from_port                = 30443
  to_port                  = 30443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s_worker.id
  source_security_group_id = aws_security_group.k8s_ingress_nlb.id
  description              = "Ingress NodePort HTTPS from public NLB"
}

resource "aws_security_group_rule" "k8s_worker_ingress_10250_from_control_plane" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s_worker.id
  source_security_group_id = aws_security_group.k8s_control_plane.id
  description              = "kubelet from control-plane nodes"
}

resource "aws_security_group_rule" "k8s_worker_ingress_4789_from_control_plane" {
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.k8s_worker.id
  source_security_group_id = aws_security_group.k8s_control_plane.id
  description              = "Overlay network from control-plane nodes"
}

resource "aws_security_group_rule" "k8s_worker_ingress_4789_from_worker" {
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.k8s_worker.id
  source_security_group_id = aws_security_group.k8s_worker.id
  description              = "Overlay network from worker nodes"
}

resource "aws_security_group_rule" "rds_postgres_from_k8s_worker" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.security.rds_sg_id
  source_security_group_id = aws_security_group.k8s_worker.id
  description              = "PostgreSQL from kubeadm worker nodes"
}

resource "aws_security_group_rule" "redis_from_k8s_worker" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis_prod.id
  source_security_group_id = aws_security_group.k8s_worker.id
  description              = "Redis from kubeadm worker nodes"
}

# ──────────────────────────────────────────────
# NLB — Internal API / Public Ingress
# ──────────────────────────────────────────────

resource "aws_lb" "k8s_apiserver_internal" {
  name               = "prod-nlb-k8s-apiserver-int"
  internal           = true
  load_balancer_type = "network"
  security_groups    = [aws_security_group.k8s_apiserver_nlb.id]
  subnets = [
    local.private_subnet_2a,
    local.private_subnet_2c,
    local.private_subnet_2b
  ]
}

resource "aws_lb_target_group" "k8s_apiserver" {
  name        = "prod-k8s-apiserver-tg"
  port        = 6443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  health_check {
    port                = "6443"
    protocol            = "TCP"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "k8s_apiserver_6443" {
  load_balancer_arn = aws_lb.k8s_apiserver_internal.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_apiserver.arn
  }
}

resource "aws_lb_target_group_attachment" "k8s_apiserver" {
  for_each = local.k8s_apiserver_targets

  target_group_arn = aws_lb_target_group.k8s_apiserver.arn
  target_id        = each.value
  port             = 6443
}

resource "aws_lb" "k8s_ingress_public" {
  name               = "prod-nlb-k8s-ingress-pub"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [aws_security_group.k8s_ingress_nlb.id]
  subnets = [
    local.public_subnet_2a,
    local.public_subnet_2c,
    local.public_subnet_2b
  ]
}

resource "aws_lb_target_group" "k8s_ingress_http" {
  name        = "prod-k8s-ingress-http-tg"
  port        = 30080
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  health_check {
    port     = "30080"
    protocol = "TCP"
  }
}

resource "aws_lb_target_group" "k8s_ingress_https" {
  name        = "prod-k8s-ingress-https-tg"
  port        = 30443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  health_check {
    port     = "30443"
    protocol = "TCP"
  }
}

resource "aws_lb_listener" "k8s_ingress_80" {
  load_balancer_arn = aws_lb.k8s_ingress_public.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_ingress_http.arn
  }
}

resource "aws_lb_listener" "k8s_ingress_443" {
  load_balancer_arn = aws_lb.k8s_ingress_public.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_ingress_https.arn
  }
}

resource "aws_lb_target_group_attachment" "k8s_ingress_http" {
  for_each = local.k8s_ingress_targets

  target_group_arn = aws_lb_target_group.k8s_ingress_http.arn
  target_id        = each.value
  port             = 30080
}

resource "aws_lb_target_group_attachment" "k8s_ingress_https" {
  for_each = local.k8s_ingress_targets

  target_group_arn = aws_lb_target_group.k8s_ingress_https.arn
  target_id        = each.value
  port             = 30443
}

# ──────────────────────────────────────────────
# AMI — Ubuntu 24.04 LTS (K8s 노드 전용)
# docker_base 커스텀 AMI와 달리 containerd 충돌 없는 순수 Ubuntu
# ──────────────────────────────────────────────

data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# ──────────────────────────────────────────────
# EC2 — K8s Nodes
# ──────────────────────────────────────────────

module "ec2_k8s_cp_2a" {
  source = "../../modules/ec2"

  environment                 = var.environment
  purpose                     = "k8s-cp-2a"
  instance_type               = "t3.medium"
  ami_id                      = data.aws_ami.ubuntu_2404.id
  subnet_id                   = local.private_subnet_2a
  security_group_ids          = [aws_security_group.k8s_control_plane.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.prod_k8s_node.name
  root_volume_size            = 50
}

module "ec2_k8s_worker_2b" {
  source = "../../modules/ec2"

  environment                 = var.environment
  purpose                     = "k8s-worker-2b"
  instance_type               = "t3.medium"
  ami_id                      = data.aws_ami.ubuntu_2404.id
  subnet_id                   = local.private_subnet_2b
  security_group_ids          = [aws_security_group.k8s_worker.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.prod_k8s_node.name
  root_volume_size            = 50
}

module "ec2_k8s_worker_2c" {
  source = "../../modules/ec2"

  environment                 = var.environment
  purpose                     = "k8s-worker-2c"
  instance_type               = "t3.medium"
  ami_id                      = data.aws_ami.ubuntu_2404.id
  subnet_id                   = local.private_subnet_2c
  security_group_ids          = [aws_security_group.k8s_worker.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.prod_k8s_node.name
  root_volume_size            = 50
}
