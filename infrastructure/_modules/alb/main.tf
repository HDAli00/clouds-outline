resource "aws_lb" "this" {
  name               = "${var.project}-${var.env}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = true

  tags = { Name = "${var.project}-${var.env}-alb" }
}

# ---------------------------------------------------------------------------
# Target group — Web process (handles Web API, WebSocket, Collaboration, Admin)
# All traffic routes here since all services are co-located in one container.
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "web" {
  name        = "${var.project}-${var.env}-web-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # Required for Fargate

  health_check {
    path                = "/_health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  stickiness {
    type    = "lb_cookie"
    enabled = true  # Required for WebSocket and Collaboration connections
  }

  tags = { Name = "${var.project}-${var.env}-web-tg" }
}

# ---------------------------------------------------------------------------
# HTTP listener
# When no certificate is provided: forward directly to the web target group.
# When a certificate is provided: redirect to HTTPS.
# ---------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = var.certificate_arn != null ? "redirect" : "forward"
    target_group_arn = var.certificate_arn == null ? aws_lb_target_group.web.arn : null

    dynamic "redirect" {
      for_each = var.certificate_arn != null ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# HTTPS listener — only created when a certificate ARN is provided.
# ---------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
