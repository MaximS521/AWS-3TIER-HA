locals {
  tags = {
    Project = var.project_name
    Repo    = "aws-3tier-ha-anon"
    Owner   = "anonymous"
  }
}

data "aws_availability_zones" "this" {
  state = "available"
}

module "network" {
  source   = "./modules/network"
  name     = var.project_name
  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.this.names, 0, 2)
  tags     = local.tags
}

module "security" {
  source = "./modules/security"
  vpc_id = module.network.vpc_id
  app_port = var.app_port
  tags   = local.tags
}

module "endpoints" {
  source    = "./modules/endpoints"
  vpc_id    = module.network.vpc_id
  subnet_ids = module.network.private_web_subnet_ids
  tags      = local.tags
}

module "compute" {
  source = "./modules/compute"
  name   = var.project_name
  vpc_id = module.network.vpc_id

  public_subnet_ids       = module.network.public_subnet_ids
  private_web_subnet_ids  = module.network.private_web_subnet_ids
  private_app_subnet_ids  = module.network.private_app_subnet_ids

  web_sg_id = module.security.web_asg_sg_id
  app_sg_id = module.security.app_asg_sg_id

  instance_profile_name = module.security.instance_profile_name

  web_instance_type = var.web_instance_type
  app_instance_type = var.app_instance_type
  app_port          = var.app_port
  tags              = local.tags
}

module "alb" {
  source = "./modules/alb"
  vpc_id = module.network.vpc_id

  public_subnet_ids      = module.network.public_subnet_ids
  private_app_subnet_ids = module.network.private_app_subnet_ids

  web_alb_sg_id = module.security.web_alb_sg_id
  app_alb_sg_id = module.security.app_alb_sg_id
  web_asg_tg_arn = module.compute.web_tg_arn
  app_asg_tg_arn = module.compute.app_tg_arn

  web_listener_https_enabled = var.web_listener_https_enabled
  web_alb_acm_arn            = var.web_alb_acm_arn
  alb_logs_s3_bucket         = var.alb_logs_s3_bucket
  waf_web_acl_arn            = var.waf_web_acl_arn

  tags = local.tags
}

module "rds" {
  source = "./modules/rds"
  name   = var.project_name

  vpc_id       = module.network.vpc_id
  subnet_ids   = module.network.db_subnet_ids
  db_sg_id     = module.security.db_sg_id
  app_sg_id    = module.security.app_asg_sg_id

  engine_version = var.rds_engine_version
  multi_az       = var.rds_multi_az
  instance_class = var.rds_instance_class
  tags           = local.tags
}
