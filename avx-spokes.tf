# Aviatrix Spoke Gateway for ROSA VPC
module "avx_spoke_rosa" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "8.2.0"

  cloud            = "AWS"
  name             = "${var.owner}${var.project_id}-rosa-spoke"
  cidr             = var.vpc1-rosa_cidr
  region           = var.aws_region
  account          = var.avx_access_account_name
  transit_gw       = module.avx_transit_vpc.transit_gateway.gw_name
  instance_size    = var.avx_spoke_instance_size
  ha_gw            = var.avx_ha_enabled

  # Use existing VPC - provide subnet CIDRs
  use_existing_vpc = true
  vpc_id           = module.rosa-vpc.vpc_id
  gw_subnet        = var.vpc1-rosa_public_subnets[0]
  hagw_subnet      = var.vpc1-rosa_public_subnets[1]
}

# Aviatrix Spoke Gateway for External VPC
module "avx_spoke_ext" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "8.2.0"

  cloud            = "AWS"
  name             = "${var.owner}${var.project_id}-ext-spoke"
  cidr             = var.vpc2-ext_cidr
  region           = var.aws_region
  account          = var.avx_access_account_name
  transit_gw       = module.avx_transit_vpc.transit_gateway.gw_name
  instance_size    = var.avx_spoke_instance_size
  ha_gw            = var.avx_ha_enabled

  # Use existing VPC - provide subnet CIDRs
  use_existing_vpc = true
  vpc_id           = module.ext-vpc.vpc_id
  gw_subnet        = var.vpc2-ext_public_subnets[0]
  hagw_subnet      = var.vpc2-ext_public_subnets[1]
}
