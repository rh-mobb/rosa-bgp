# Static secondary IP allocations for BGP router nodes
# These IPs are reserved via CIDR reservations and assigned to router node ENIs
# by the lifecycle-static-secondary-ip DaemonSet controller

# Variables for static BGP router IPs (choose from each subnet range)
# For 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24 subnets:
# Pick IPs that won't conflict with existing allocations (e.g., .10 in each)

locals {
  bgp_secondary_ip_subnet1 = "10.0.1.10"
  bgp_secondary_ip_subnet2 = "10.0.2.10"
  bgp_secondary_ip_subnet3 = "10.0.3.10"
}

# Reserve IP in subnet 1
resource "aws_ec2_subnet_cidr_reservation" "bgp_router_subnet1" {
  cidr_block       = "${local.bgp_secondary_ip_subnet1}/32"
  reservation_type = "explicit"
  subnet_id        = module.rosa-vpc.private_subnets[0]

  description = "BGP router secondary IP for subnet 1"
}

# Reserve IP in subnet 2
resource "aws_ec2_subnet_cidr_reservation" "bgp_router_subnet2" {
  cidr_block       = "${local.bgp_secondary_ip_subnet2}/32"
  reservation_type = "explicit"
  subnet_id        = module.rosa-vpc.private_subnets[1]

  description = "BGP router secondary IP for subnet 2"
}

# Reserve IP in subnet 3
resource "aws_ec2_subnet_cidr_reservation" "bgp_router_subnet3" {
  cidr_block       = "${local.bgp_secondary_ip_subnet3}/32"
  reservation_type = "explicit"
  subnet_id        = module.rosa-vpc.private_subnets[2]

  description = "BGP router secondary IP for subnet 3"
}

# Output the reserved IPs for use by deployment scripts
output "bgp_secondary_ip_subnet1" {
  value       = local.bgp_secondary_ip_subnet1
  description = "Reserved BGP router secondary IP for subnet 1"
}

output "bgp_secondary_ip_subnet2" {
  value       = local.bgp_secondary_ip_subnet2
  description = "Reserved BGP router secondary IP for subnet 2"
}

output "bgp_secondary_ip_subnet3" {
  value       = local.bgp_secondary_ip_subnet3
  description = "Reserved BGP router secondary IP for subnet 3"
}
