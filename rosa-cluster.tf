module "hcp" {
  source = "terraform-redhat/rosa-hcp/rhcs"
  version = ">= 1.6.2"

  cluster_name           = "${var.rosa_cluster_name}"
  openshift_version      = var.rosa_openshift_version
  machine_cidr           = module.rosa-vpc.vpc_cidr_block
  aws_subnet_ids         = concat(module.rosa-vpc.public_subnets, module.rosa-vpc.private_subnets)
  aws_availability_zones = module.rosa-vpc.azs
  replicas               = length(module.rosa-vpc.azs)
  create_admin_user      = true

  // STS configuration
  create_account_roles  = true
  account_role_prefix   = "${var.rosa_cluster_name}-role"
  create_oidc           = true
  create_operator_roles = true
  operator_role_prefix  = "${var.rosa_cluster_name}-operator"

  // FSx access security group (applied to all worker nodes)
  // Note: This parameter is immutable after cluster creation
  aws_additional_compute_security_group_ids = var.enable_fsx_ontap ? [aws_security_group.rosa_worker_fsx_access_sg[0].id] : null
}

# outputs ROSA cluster
output "rosa_api_url" {
  value       = module.hcp.cluster_api_url
}
output "rosa_console_url" {
  value       = module.hcp.cluster_console_url
}
output "rosa_cluster_admin_password" {
  value       = nonsensitive(module.hcp.cluster_admin_password)
  #  sensitive   = true
}
output "rosa_cluster_id" {
  description = "ROSA cluster ID for resource tagging"
  value       = module.hcp.cluster_id
}


### Create Security Group to allow ALL traffic from rfc1918
resource "aws_security_group" "rosa_rfc1918_sg" {
  name_prefix = "rosa-virt-allow-rfc1918-sg-"
  description = "Allow traffic from all IPv4 private prefixes"
  vpc_id      = module.rosa-vpc.vpc_id

  # Ingress: Allow ALL traffic from rfc1918
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
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
    Name = "${var.rosa_cluster_name}-allow-ALL-from-rfc1918-SG"
    }
  )
}

# Allow from ALL to enable IGW traffic for POD networks
resource "aws_security_group" "rosa_allow_from_all_sg" {
  name_prefix = "rosa-virt-allow-from-ALL-sg-"
  description = "Allow traffic from all"
  vpc_id      = module.rosa-vpc.vpc_id

  # Ingress: Allow ALL
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
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
      Name = "${var.rosa_cluster_name}-allow-ALL-from-ALL-SG"
    }
  )
}

# Security Group for FSx access - applied to all worker nodes
resource "aws_security_group" "rosa_worker_fsx_access_sg" {
  count = var.enable_fsx_ontap ? 1 : 0

  name_prefix = "rosa-virt-worker-fsx-access-sg-"
  description = "Security group for ROSA workers to access FSx ONTAP"
  vpc_id      = module.rosa-vpc.vpc_id

  # No ingress rules - this SG acts as source identity for FSx security group

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${var.rosa_cluster_name}-worker-fsx-access-SG"
    }
  )
}

