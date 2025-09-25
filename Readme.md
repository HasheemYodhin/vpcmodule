# Terraform AWS VPC Module

A Terraform module for creating a comprehensive VPC infrastructure on AWS.

## Features

- Creates VPC with configurable CIDR block
- Public, private, and database subnets across multiple availability zones
- Internet Gateway for public subnets
- NAT Gateways for private subnets (configurable)
- Route tables and associations
- Optional VPN Gateway support
- Comprehensive tagging

## Usage

```hcl
module "vpc" {
  source = "your-username/vpc/aws"

  name               = "my-vpc"
  cidr_block         = "10.0.0.0/16"
  az_count           = 2
  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Environment = "production"
  }
}