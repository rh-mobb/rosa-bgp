module "tgw1" {
  source  = "terraform-aws-modules/transit-gateway/aws"

  name        = "${var.owner}${var.project_id}-tgw1"
  description = "TGW for testing ROSA BGP"

  vpc_attachments = {
    ext-vpc = {
      vpc_id       = module.ext-vpc.vpc_id
      subnet_ids   = module.ext-vpc.private_subnets
      transit_gateway_default_route_table_association = false
      transit_gateway_default_route_table_propagation = false
      tags = merge (
        local.tags,
        {
        Name = "${var.owner}${var.project_id}-tgw1-ext-vpc_attach"
        }
      )
    }
    rosa-vpc = {
      vpc_id       = module.rosa-vpc.vpc_id
      subnet_ids   = module.rosa-vpc.private_subnets
      transit_gateway_default_route_table_association = false
      transit_gateway_default_route_table_propagation = false
      tgw_routes = [
      {
        destination_cidr_block = "10.100.0.0/16"
      },
      {
        destination_cidr_block = "10.101.0.0/16"
      }
    ]
      tags = merge (
        local.tags,
        {
        Name = "${var.owner}${var.project_id}-tgw1-rosa-vpc_attach"
        }
      )
    }

  }


  tags = merge (
    local.tags,
    {
    }
  )
}

# add static routes to VPC private route tables
# rosa-vpc CIDR into ext-vpc subnet RTs
resource "aws_route" "ext-vpc_tgw_route_rosa-vpc_cidr_private" {
  count = length(module.ext-vpc.private_route_table_ids)
  destination_cidr_block = module.rosa-vpc.vpc_cidr_block
  transit_gateway_id = module.tgw1.ec2_transit_gateway_id
  route_table_id = module.ext-vpc.private_route_table_ids[count.index]
}
resource "aws_route" "ext-vpc_tgw_route_rosa-vpc_cidr_prublic" {
  count = length(module.ext-vpc.public_route_table_ids)
  destination_cidr_block = module.rosa-vpc.vpc_cidr_block
  transit_gateway_id = module.tgw1.ec2_transit_gateway_id
  route_table_id = module.ext-vpc.public_route_table_ids[count.index]
}

# rosa-ext CIDR into rosa-vpc subnet RTs
resource "aws_route" "rosa-vpc_tgw_route_ext-vpc_cidr_private" {
  count = length(module.rosa-vpc.private_route_table_ids)
  destination_cidr_block = module.ext-vpc.vpc_cidr_block
  transit_gateway_id = module.tgw1.ec2_transit_gateway_id
  route_table_id = module.rosa-vpc.private_route_table_ids[count.index]
}
resource "aws_route" "rosa-vpc_tgw_route_ext-vpc_cidr_public" {
  count = length(module.rosa-vpc.public_route_table_ids)
  destination_cidr_block = module.ext-vpc.vpc_cidr_block
  transit_gateway_id = module.tgw1.ec2_transit_gateway_id
  route_table_id = module.rosa-vpc.public_route_table_ids[count.index]
}

#CUDN prefix into ext-vpc subnet RTs (can be also summarized e.g. as single route 10.0.0.0/8)
# private rts
resource "aws_route" "ext-vpc_tgw_route_cudn1_private" {
  count = length(module.ext-vpc.private_route_table_ids)
  destination_cidr_block = "10.100.0.0/16"
  transit_gateway_id = module.tgw1.ec2_transit_gateway_id
  route_table_id = module.ext-vpc.private_route_table_ids[count.index]
}
# prublic rts
resource "aws_route" "ext-vpc_tgw_route_cudn1_public" {
  count = length(module.ext-vpc.public_route_table_ids)
  destination_cidr_block = "10.100.0.0/16"
  transit_gateway_id = module.tgw1.ec2_transit_gateway_id
  route_table_id = module.ext-vpc.public_route_table_ids[count.index]
}

# CUDN2 prefix into ext-vpc subnet RTs
# private rts
resource "aws_route" "ext-vpc_tgw_route_cudn2_private" {
  count = length(module.ext-vpc.private_route_table_ids)
  destination_cidr_block = "10.101.0.0/16"
  transit_gateway_id = module.tgw1.ec2_transit_gateway_id
  route_table_id = module.ext-vpc.private_route_table_ids[count.index]
}
# public rts
resource "aws_route" "ext-vpc_tgw_route_cudn2_public" {
  count = length(module.ext-vpc.public_route_table_ids)
  destination_cidr_block = "10.101.0.0/16"
  transit_gateway_id = module.tgw1.ec2_transit_gateway_id
  route_table_id = module.ext-vpc.public_route_table_ids[count.index]
}
