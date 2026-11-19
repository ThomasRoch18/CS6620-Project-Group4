# ---------------------------------------
# Latest Amazon Linux 2023 AMI
# ---------------------------------------
data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------------------------------------
# Application Load Balancer
# ---------------------------------------
resource "aws_lb" "dashboard" {
  name               = "cs6620-dashboard-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-dashboard-alb"
  }
}

# ---------------------------------------
# Dashboard Target Group
# ---------------------------------------
resource "aws_lb_target_group" "dashboard" {
  name        = "cs6620-dashboard-tg"
  port        = 5000
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-dashboard-tg"
  }
}

# ---------------------------------------
# ALB HTTP Listener
# ---------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.dashboard.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboard.arn
  }
}

# ---------------------------------------
# EC2 Launch Template
# ---------------------------------------
resource "aws_launch_template" "dashboard" {
  name_prefix   = "cs6620-dashboard-"
  image_id      = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type = "t3.micro"

  vpc_security_group_ids = [
    aws_security_group.dashboard.id
  ]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Temporary dashboard placeholder.
  # Replace with the real Flask deployment later.
  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y python3

    mkdir -p /opt/dashboard

    echo "<h1>CS6620 Security Scanning Dashboard</h1><p>Infrastructure test instance</p>" > /opt/dashboard/index.html

    cat > /etc/systemd/system/dashboard-placeholder.service <<'SERVICE'
    [Unit]
    Description=Temporary Dashboard HTTP Server
    After=network.target

    [Service]
    WorkingDirectory=/opt/dashboard
    ExecStart=/usr/bin/python3 -m http.server 5000 --bind 0.0.0.0
    Restart=always

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable --now dashboard-placeholder
  EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.project_name}-dashboard"
    }
  }


  iam_instance_profile {
    arn = aws_iam_instance_profile.dashboard.arn
  }

}

# ---------------------------------------
# EC2 Auto Scaling Group
# ---------------------------------------
resource "aws_autoscaling_group" "dashboard" {
  name = "${var.project_name}-dashboard-asg"

  min_size         = 1
  max_size         = 2
  desired_capacity = 2

  vpc_zone_identifier = aws_subnet.private[*].id

  target_group_arns = [
    aws_lb_target_group.dashboard.arn
  ]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.dashboard.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-dashboard"
    propagate_at_launch = true
  }
}
