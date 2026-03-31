# BGP router IPs are now static secondary IPs defined in vpc1-bgp-secondary-ips.tf
# These are assigned to router node ENIs by the lifecycle-static-secondary-ip controller
locals {
  router1_ip = local.bgp_secondary_ip_subnet1
  router2_ip = local.bgp_secondary_ip_subnet2
  router3_ip = local.bgp_secondary_ip_subnet3
}

# create route server peers for router worker node in subnet1

resource "aws_vpc_route_server_peer" "subnet1_ep1_rosa_router1" {
  route_server_endpoint_id = aws_vpc_route_server_endpoint.vpc1-rs1-subnet1-ep1.route_server_endpoint_id
  peer_address = local.router1_ip
  depends_on = [
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet1,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet2,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet3
  ]
  bgp_options {
    peer_asn = var.rosa_bgp_asn
    peer_liveness_detection = "bgp-keepalive" #need to check why bfd isnt working
  }
  tags = merge(
    local.tags,
    {
      Name = "rs1-subnet1_ep1_rosa_router1_peer"
    }
  )
}
resource "aws_vpc_route_server_peer" "subnet1_ep2_rosa_router1" {
  route_server_endpoint_id = aws_vpc_route_server_endpoint.vpc1-rs1-subnet1-ep2.route_server_endpoint_id
  peer_address = local.router1_ip
  depends_on = [
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet1,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet2,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet3
  ]
  bgp_options {
    peer_asn = var.rosa_bgp_asn
    peer_liveness_detection = "bgp-keepalive" #need to check why bfd isnt working
  }
  tags = merge(
    local.tags,
    {
      Name = "rs1_subnet1_ep2_rosa_router1_peer"
    }
  )
}

resource "aws_vpc_route_server_peer" "subnet2_ep1_rosa_router2" {
  route_server_endpoint_id = aws_vpc_route_server_endpoint.vpc1-rs1-subnet2-ep1.route_server_endpoint_id
  peer_address = local.router2_ip
  depends_on = [
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet1,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet2,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet3
  ]
  bgp_options {
    peer_asn = var.rosa_bgp_asn
    peer_liveness_detection = "bgp-keepalive" #need to check why bfd isnt working
  }
  tags = merge(
    local.tags,
    {
      Name = "rs1_subnet2_ep1_rosa_router2_peer"
    }
  )
}
resource "aws_vpc_route_server_peer" "subnet2_ep2_rosa_router2" {
  route_server_endpoint_id = aws_vpc_route_server_endpoint.vpc1-rs1-subnet2-ep2.route_server_endpoint_id
  peer_address = local.router2_ip
  depends_on = [
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet1,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet2,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet3
  ]
  bgp_options {
    peer_asn = var.rosa_bgp_asn
    peer_liveness_detection = "bgp-keepalive" #need to check why bfd isnt working
  }
  tags = merge(
    local.tags,
    {
      Name = "rs1_subnet2_ep2_rosa_router2_peer"
    }
  )
}

resource "aws_vpc_route_server_peer" "subnet3_ep1_rosa_router3" {
  route_server_endpoint_id = aws_vpc_route_server_endpoint.vpc1-rs1-subnet3-ep1.route_server_endpoint_id
  peer_address = local.router3_ip
  depends_on = [
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet1,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet2,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet3
  ]
  bgp_options {
    peer_asn = var.rosa_bgp_asn
    peer_liveness_detection = "bgp-keepalive" #need to check why bfd isnt working
  }
  tags = merge(
    local.tags,
    {
    Name = "rs1_subnet3_ep1_rosa_router3_peer"
    }
  )
}
resource "aws_vpc_route_server_peer" "subnet3_ep2_rosa_router3" {
  route_server_endpoint_id = aws_vpc_route_server_endpoint.vpc1-rs1-subnet3-ep2.route_server_endpoint_id
  peer_address = local.router3_ip
  depends_on = [
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet1,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet2,
    aws_ec2_subnet_cidr_reservation.bgp_router_subnet3
  ]
  bgp_options {
    peer_asn = var.rosa_bgp_asn
    peer_liveness_detection = "bgp-keepalive" #need to check why bfd isnt working
  }
  tags = merge(
    local.tags,
    {
      Name = "rs1_subnet3_ep2_rosa_router3_peer"
    }
  )
}
