variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "db_sg_id" { type = string }
variable "app_sg_id" { type = string }
variable "engine_version" { type = string }
variable "multi_az" { type = bool }
variable "instance_class" { type = string }
variable "tags" { type = map(string) }

resource "random_password" "db" {
  length  = 20
  special = true
}

resource "aws_secretsmanager_secret" "db" {
  name = "${var.name}/rds/mysql"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({ username = "admin", password = random_password.db.result })
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-mysql-params"
  family = "mysql${var.engine_version}"
  tags   = var.tags
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_db_instance" "this" {
  identifier             = "${var.name}-mysql"
  engine                 = "mysql"
  engine_version         = var.engine_version
  instance_class         = var.instance_class
  username               = "admin"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  multi_az               = var.multi_az
  allocated_storage      = 20
  skip_final_snapshot    = true
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  deletion_protection    = false
  tags                   = var.tags
}

output "db_endpoint" { value = aws_db_instance.this.address }
output "secret_arn"  { value = aws_secretsmanager_secret.db.arn }
