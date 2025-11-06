output "vpc_id"              { value = module.network.vpc_id }
output "public_alb_dns_name" { value = module.alb.web_alb_dns }
output "app_alb_dns_name"    { value = module.alb.app_alb_dns }
output "rds_endpoint"        { value = module.rds.db_endpoint }
