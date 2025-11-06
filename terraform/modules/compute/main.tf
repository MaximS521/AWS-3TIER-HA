variable "name" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_web_subnet_ids" { type = list(string) }
variable "private_app_subnet_ids" { type = list(string) }

variable "web_sg_id" { type = string }
variable "app_sg_id" { type = string }

variable "instance_profile_name" { type = string }

variable "web_instance_type" { type = string }
variable "app_instance_type" { type = string }
variable "app_port" { type = number }

variable "tags" { type = map(string) }

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"] # Amazon
  filter { name = "name" values = ["al2023-ami-*-x86_64"] }
}

# Target Groups (ALBs are created in alb module; but TGs live here to bind ASGs)
resource "aws_lb_target_group" "web" {
  name     = "${var.name}-tg-web"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    path = "/"
    matcher = "200-399"
  }
  tags = var.tags
}

resource "aws_lb_target_group" "app" {
  name     = "${var.name}-tg-app"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    path = "/health"
    matcher = "200-399"
  }
  tags = var.tags
}

# Launch Templates
resource "aws_launch_template" "web" {
  name_prefix   = "${var.name}-lt-web-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.web_instance_type
  iam_instance_profile { name = var.instance_profile_name }
  vpc_security_group_ids = [var.web_sg_id]
  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx
    echo "<h1>${var.name}: web tier</h1>" > /usr/share/nginx/html/index.html
    systemctl enable nginx
    systemctl start nginx
  EOF
  )
  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, { Tier = "web" })
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.name}-lt-app-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.app_instance_type
  iam_instance_profile { name = var.instance_profile_name }
  vpc_security_group_ids = [var.app_sg_id]
  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y python3
    cat >/opt/app.py <<PY
    from http.server import BaseHTTPRequestHandler, HTTPServer
    class H(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/health":
                self.send_response(200); self.end_headers(); self.wfile.write(b"ok"); return
            self.send_response(200); self.end_headers(); self.wfile.write(b"app tier says hi")
    HTTPServer(("", ${var.app_port}), H).serve_forever()
    PY
    cat >/etc/systemd/system/app.service <<SVC
    [Unit]
    Description=Simple App
    After=network.target
    [Service]
    ExecStart=/usr/bin/python3 /opt/app.py
    Restart=always
    [Install]
    WantedBy=multi-user.target
    SVC
    systemctl daemon-reload
    systemctl enable app
    systemctl start app
  EOF
  )
  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, { Tier = "app" })
  }
}

resource "aws_autoscaling_group" "web" {
  name                      = "${var.name}-asg-web"
  desired_capacity          = 2
  max_size                  = 4
  min_size                  = 2
  vpc_zone_identifier       = var.private_web_subnet_ids
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "EC2"
  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }
  tag { key = "Name" value = "${var.name}-web" propagate_at_launch = true }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.name}-asg-app"
  desired_capacity          = 2
  max_size                  = 4
  min_size                  = 2
  vpc_zone_identifier       = var.private_app_subnet_ids
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "EC2"
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  tag { key = "Name" value = "${var.name}-app" propagate_at_launch = true }
}

# Simple Target Tracking policies (CPU 50%)
resource "aws_autoscaling_policy" "web_cpu" {
  name                   = "${var.name}-web-cpu-tt"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}

resource "aws_autoscaling_policy" "app_cpu" {
  name                   = "${var.name}-app-cpu-tt"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}

output "web_tg_arn" { value = aws_lb_target_group.web.arn }
output "app_tg_arn" { value = aws_lb_target_group.app.arn }
