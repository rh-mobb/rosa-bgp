# VPC Endpoints for SSM access in ROSA VPC

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints_sg" {
  name_prefix = "${var.owner}${var.project_id}-vpce-sg-"
  description = "Security group for VPC endpoints (SSM)"
  vpc_id      = module.rosa-vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc1-rosa_cidr]
    description = "HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${var.owner}${var.project_id}-vpce-sg"
    }
  )
}

# SSM VPC Endpoint
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = module.rosa-vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.rosa-vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "${var.owner}${var.project_id}-ssm-endpoint"
    }
  )
}

# SSM Messages VPC Endpoint
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = module.rosa-vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.rosa-vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "${var.owner}${var.project_id}-ssmmessages-endpoint"
    }
  )
}

# EC2 Messages VPC Endpoint (required for Session Manager)
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = module.rosa-vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.rosa-vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "${var.owner}${var.project_id}-ec2messages-endpoint"
    }
  )
}

output "ssm_vpc_endpoint_id" {
  description = "ID of SSM VPC endpoint"
  value       = aws_vpc_endpoint.ssm.id
}
