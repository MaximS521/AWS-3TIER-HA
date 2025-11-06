project_name = "three-tier-ha"
aws_region   = "us-east-1"

vpc_cidr = "10.42.0.0/16"

# Lock this to your admin CIDR when you enable any restricted rules
admin_cidr_blocks = ["203.0.113.0/24"]

# Web & App ports
web_listener_https_enabled = false
web_alb_acm_arn            = ""

app_port = 8080

# Instance types
web_instance_type = "t3.micro"
app_instance_type = "t3.micro"

# RDS
rds_engine_version = "8.0"
rds_multi_az       = true
rds_instance_class = "db.t3.micro"

# Optional: enable WAF attachment to Internet ALB (provide web acl arn)
waf_web_acl_arn = ""

# Logging (set bucket name to enable ALB access logs)
alb_logs_s3_bucket = ""
