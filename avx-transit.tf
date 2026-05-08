# Aviatrix Transit VPC and Gateway
module "avx_transit_vpc" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "8.2.0"

  cloud             = "AWS"
  region            = var.aws_region
  cidr              = var.avx_transit_vpc_cidr
  account           = var.avx_access_account_name
  name              = "${var.owner}${var.project_id}-avx-transit"
  instance_size     = var.avx_transit_instance_size
  ha_gw             = var.avx_ha_enabled
  connected_transit = true
}
