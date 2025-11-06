variable "project_name" { type = string }
variable "aws_region"   { type = string }

variable "vpc_cidr" { type = string }

variable "admin_cidr_blocks" {
  description = "Admin CIDR(s) if you later enable restricted rules"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "web_listener_https_enabled" { type = bool  default = false }
variable "web_alb_acm_arn"            { type = string default = "" }
variable "app_port"                    { type = number default = 8080 }

variable "web_instance_type" { type = string default = "t3.micro" }
variable "app_instance_type" { type = string default = "t3.micro" }

variable "rds_engine_version" { type = string default = "8.0" }
variable "rds_multi_az"       { type = bool   default = true }
variable "rds_instance_class" { type = string default = "db.t3.micro" }

variable "waf_web_acl_arn" { type = string default = "" }

variable "alb_logs_s3_bucket" { type = string default = "" }
