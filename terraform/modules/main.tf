variable "vpc_id" { type = string }
variable "app_port" { type = number }
variable "tags" { type = map(string) }

# Web ALB SG (80/443 from anywhere)
resource "aws_security_group" "web_alb" {
  name        = "sg-web-alb"
  description = "Internet-facing ALB"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "sg-web-alb" })
}

# Web ASG SG (only from web ALB SG on 80)
resource "aws_security_group" "web_asg" {
  name   = "sg-web-asg"
  vpc_id = var.vpc_id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.web_alb.id]
  }
  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
  tags = merge(var.tags, { Name = "sg-web-asg" })
}

# App ALB SG (only from web ASG SG on app port)
resource "aws_security_group" "app_alb" {
  name   = "sg-app-alb"
  vpc_id = var.vpc_id
  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web_asg.id]
  }
  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
  tags = merge(var.tags, { Name = "sg-app-alb" })
}

# App ASG SG (only from app ALB SG on app port)
resource "aws_security_group" "app_asg" {
  name   = "sg-app-asg"
  vpc_id = var.vpc_id
  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app_alb.id]
  }
  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
  tags = merge(var.tags, { Name = "sg-app-asg" })
}

# DB SG (only from app ASG SG on 3306)
resource "aws_security_group" "db" {
  name   = "sg-db"
  vpc_id = var.vpc_id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_asg.id]
  }
  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
  tags = merge(var.tags, { Name = "sg-db" })
}

# IAM role for SSM
resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
  tags = var.tags
}

output "web_alb_sg_id" { value = aws_security_group.web_alb.id }
output "web_asg_sg_id" { value = aws_security_group.web_asg.id }
output "app_alb_sg_id" { value = aws_security_group.app_alb.id }
output "app_asg_sg_id" { value = aws_security_group.app_asg.id }
output "db_sg_id"      { value = aws_security_group.db.id }

output "instance_profile_name" { value = aws_iam_instance_profile.ec2_ssm_profile.name }
