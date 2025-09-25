# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Determine AZs to use
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, var.az_count)
  
  # Calculate subnet CIDRs if not provided
  public_subnets = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [
    for i in range(length(local.azs)) : cidrsubnet(var.cidr_block, 8, i)
  ]
  
  private_subnets = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [
    for i in range(length(local.azs)) : cidrsubnet(var.cidr_block, 8, i + 100)
  ]
  
  database_subnets = length(var.database_subnet_cidrs) > 0 ? var.database_subnet_cidrs : [
    for i in range(length(local.azs)) : cidrsubnet(var.cidr_block, 8, i + 200)
  ]
  
  # Base tags
  base_tags = merge(
    {
      "Module"    = "terraform-aws-vpc"
      "Terraform" = "true"
    },
    var.tags
  )
}

# VPC Resource
resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  instance_tenancy     = var.instance_tenancy
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(
    {
      "Name" = var.name
    },
    local.base_tags
  )
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    {
      "Name" = "${var.name}-igw"
    },
    local.base_tags
  )
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(local.public_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(
    {
      "Name" = "${var.name}-public-${local.azs[count.index]}"
      "Type" = "public"
    },
    local.base_tags
  )
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    {
      "Name" = "${var.name}-public"
    },
    local.base_tags
  )
}

# Public Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(local.private_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(
    {
      "Name" = "${var-name}-private-${local.azs[count.index]}"
      "Type" = "private"
    },
    local.base_tags
  )
}

# Database Subnets
resource "aws_subnet" "database" {
  count = length(local.database_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.database_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(
    {
      "Name" = "${var.name}-database-${local.azs[count.index]}"
      "Type" = "database"
    },
    local.base_tags
  )
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(local.private_subnets)) : 0

  domain = "vpc"

  tags = merge(
    {
      "Name" = "${var.name}-nat-${local.azs[count.index]}"
    },
    local.base_tags
  )
}

# NAT Gateways
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(local.private_subnets)) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    {
      "Name" = "${var.name}-nat-${local.azs[count.index]}"
    },
    local.base_tags
  )

  depends_on = [aws_internet_gateway.main]
}

# Private Route Tables
resource "aws_route_table" "private" {
  count = length(local.private_subnets)

  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
    }
  }

  tags = merge(
    {
      "Name" = "${var.name}-private-${local.azs[count.index]}"
    },
    local.base_tags
  )
}

# Private Route Table Associations
resource "aws_route_table_association" "private" {
  count = length(local.private_subnets)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Database Route Tables
resource "aws_route_table" "database" {
  count = length(local.database_subnets)

  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
    }
  }

  tags = merge(
    {
      "Name" = "${var.name}-database-${local.azs[count.index]}"
    },
    local.base_tags
  )
}

# Database Route Table Associations
resource "aws_route_table_association" "database" {
  count = length(local.database_subnets)

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database[count.index].id
}

# VPN Gateway (if enabled)
resource "aws_vpn_gateway" "main" {
  count = var.enable_vpn_gateway ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = merge(
    {
      "Name" = "${var.name}-vgw"
    },
    local.base_tags
  )
}