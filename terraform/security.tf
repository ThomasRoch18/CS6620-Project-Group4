# ---------------------------------------
# ALB Security Group
# ---------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the public ALB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# Allow HTTP requests from the Internet
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow public HTTP traffic"

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}

# Allow ALB to reach the dashboard
resource "aws_vpc_security_group_egress_rule" "alb_to_dashboard" {
  security_group_id = aws_security_group.alb.id
  description       = "Forward traffic to Flask dashboard"

  referenced_security_group_id = aws_security_group.dashboard.id
  from_port                    = 5000
  to_port                      = 5000
  ip_protocol                  = "tcp"
}


# ---------------------------------------
# EC2 Dashboard Security Group
# ---------------------------------------
resource "aws_security_group" "dashboard" {
  name        = "${var.project_name}-dashboard-sg"
  description = "Security group for EC2 Flask dashboard"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-dashboard-sg"
  }
}

# Only the ALB can access the dashboard
resource "aws_vpc_security_group_ingress_rule" "dashboard_from_alb" {
  security_group_id = aws_security_group.dashboard.id
  description       = "Allow HTTP from ALB"

  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 5000
  to_port                      = 5000
  ip_protocol                  = "tcp"
}

# Allow outbound traffic for AWS APIs and dependencies
resource "aws_vpc_security_group_egress_rule" "dashboard_outbound" {
  security_group_id = aws_security_group.dashboard.id
  description       = "Allow dashboard outbound traffic"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# ---------------------------------------
# ECS PenTest Security Group
# ---------------------------------------
resource "aws_security_group" "pentest" {
  name        = "${var.project_name}-pentest-sg"
  description = "Security group for ECS PenTest tasks"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-pentest-sg"
  }
}

# Allow outbound connections for authorized scans, container dependencies and AWS service access
resource "aws_vpc_security_group_egress_rule" "pentest_outbound" {
  security_group_id = aws_security_group.pentest.id
  description       = "Allow outbound traffic from PenTest tasks"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}
