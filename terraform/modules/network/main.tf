variable "name" { type = string }
variable "vpc_cidr" { type = string }
variable "azs" { type = list(string) }
variable "tags" { type = map(string) }

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(var.tags, { Name = "${var.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = merge(var.tags, { Name = "${var.name}-igw" })
}

# Subnets: public, private-web, private-app, db (2 AZs => 6 subnets total here: pub 2, web 2, app 2, db 2 = 8; but we'll do 8)
# We'll create 8 subnets: 2 public, 2 private-web, 2 private-app, 2 db
locals {
  cidr_pub  = cidrsubnet(var.vpc_cidr, 4, 0)
  cidr_web  = cidrsubnet(var.vpc_cidr, 4, 1)
  cidr_app  = cidrsubnet(var.vpc_cidr, 4, 2)
  cidr_db   = cidrsubnet(var.vpc_cidr, 4, 3)
}

resource "aws_subnet" "public" {
  for_each = { for idx, az in var.azs : idx => az }
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(local.cidr_pub, 1, each.key)
  availability_zone       = each.value
  map_public_ip_on_launch = true
  tags = merge(var.tags, { Name = "${var.name}-public-${each.value}" })
}

resource "aws_subnet" "private_web" {
  for_each = { for idx, az in var.azs : idx => az }
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(local.cidr_web, 1, each.key)
  availability_zone = each.value
  tags = merge(var.tags, { Name = "${var.name}-priv-web-${each.value}" })
}

resource "aws_subnet" "private_app" {
  for_each = { for idx, az in var.azs : idx => az }
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(local.cidr_app, 1, each.key)
  availability_zone = each.value
  tags = merge(var.tags, { Name = "${var.name}-priv-app-${each.value}" })
}

resource "aws_subnet" "db" {
  for_each = { for idx, az in var.azs : idx => az }
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(local.cidr_db, 1, each.key)
  availability_zone = each.value
  tags = merge(var.tags, { Name = "${var.name}-db-${each.value}" })
}

# NAT per AZ
resource "aws_eip" "nat" {
  for_each = aws_subnet.public
  domain = "vpc"
  tags = merge(var.tags, { Name = "${var.name}-eip-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each      = aws_subnet.public
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })
  depends_on = [aws_internet_gateway.this]
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-rt-public" })
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private route tables per AZ to their local NAT
resource "aws_route_table" "private" {
  for_each = { for idx, s in aws_subnet.private_web : idx => s }
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-rt-private-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each               = aws_route_table.private
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

# Associate both private-web and private-app subnets in each AZ with that AZ's private RT
resource "aws_route_table_association" "priv_web_assoc" {
  for_each       = { for idx, s in aws_subnet.private_web : idx => s }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table_association" "priv_app_assoc" {
  for_each       = { for idx, s in aws_subnet.private_app : idx => s }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# DB subnets: no default route to internet
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnet-grp"
  subnet_ids = [for s in aws_subnet.db : s.value.id]
  tags       = merge(var.tags, { Name = "${var.name}-db-subnet-grp" })
}

output "vpc_id" { value = aws_vpc.this.id }

output "public_subnet_ids"       { value = [for s in aws_subnet.public      : s.value.id] }
output "private_web_subnet_ids"  { value = [for s in aws_subnet.private_web : s.value.id] }
output "private_app_subnet_ids"  { value = [for s in aws_subnet.private_app : s.value.id] }
output "db_subnet_ids"           { value = [for s in aws_subnet.db          : s.value.id] }
output "db_subnet_group_name"    { value = aws_db_subnet_group.this.name }
