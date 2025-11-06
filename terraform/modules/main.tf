variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_app_subnet_ids" { type = list(string) }

variable "web_alb_sg_id" { type = string }
variable "app_alb_sg_id" { type = string }

variable "web_asg_tg_arn" { type = string }
variable "app_asg_tg_arn" { type = string }

variable "web_listener_https_enabled" { type = bool }
variable "web_alb_acm_arn"            { type = string }
variable "alb_logs_s3_bucket"         { type = string }
variable "waf_web_acl_arn"            { type = string }

variable "tags" { type = map(string) }

resource "aws_lb" "web" {
  name               = "alb-web"
  load_balancer_type = "application"
  security_groups    = [var.web_alb_sg_id]
  subnets            = var.public_subnet_ids
  dynamic "access_logs" {
    for_each = var.alb_logs_s3_bucket == "" ? [] : [1]
    content {
      bucket  = var.alb_logs_s3_bucket
      enabled = true
    }
  }
  tags = var.tags
}

resource "aws_lb_listener" "web_http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = var.web_asg_tg_arn
  }
}

resource "aws_lb_listener" "web_https" {
  count             = var.web_listener_https_enabled ? 1 : 0
  load_balancer_arn = aws_lb.web.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.web_alb_acm_arn
  default_action {
    type = "forward"
    target_group_arn = var.web_asg_tg_arn
  }
}

# Internal ALB for app tier
resource "aws_lb" "app" {
  name               = "alb-app"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.app_alb_sg_id]
  subnets            = var.private_app_subnet_ids
  tags = var.tags
}

resource "aws_lb_listener" "app_http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = var.app_asg_tg_arn
  }
}

# Optional WAF association
resource "aws_wafv2_web_acl_association" "web" {
  count        = var.waf_web_acl_arn == "" ? 0 : 1
  resource_arn = aws_lb.web.arn
  web_acl_arn  = var.waf_web_acl_arn
}

output "web_alb_dns" { value = aws_lb.web.dns_name }
output "app_alb_dns" { value = aws_lb.app.dns_name }
