# ──────────────────────────────────────────────
# Launch Template
# ──────────────────────────────────────────────

resource "aws_launch_template" "this" {
  name_prefix   = "${var.environment}-lt-${var.purpose}-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.manage_key_pair ? aws_key_pair.this[0].key_name : var.key_name

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = var.security_group_ids
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.this.name
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(templatefile(
    "${path.module}/templates/user_data.sh.tpl",
    {
      environment = var.environment
      aws_region  = var.aws_region
      app_port    = var.app_port
    }
  ))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.environment}-ec2-${var.purpose}"
    }
  }
}

# ──────────────────────────────────────────────
# Auto Scaling Group
# ──────────────────────────────────────────────

resource "aws_autoscaling_group" "this" {
  name                = "${var.environment}-asg-${var.purpose}"
  vpc_zone_identifier = var.subnet_ids

  min_size         = var.min_size
  desired_capacity = var.desired_size
  max_size         = var.max_size

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = var.health_check_grace_period

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.environment}-ec2-${var.purpose}"
    propagate_at_launch = true
  }
}

# ──────────────────────────────────────────────
# Scaling Policy — Target Tracking (CPU)
# ──────────────────────────────────────────────

resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.environment}-asg-${var.purpose}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}
