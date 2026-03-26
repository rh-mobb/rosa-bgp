module "ext-vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.owner}${var.project_id}-vpc2-ext"
  cidr = var.vpc2-ext_cidr

  azs = length(var.azs) > 0 ? var.azs : ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = var.vpc2-ext_private_subnets
  public_subnets  = var.vpc2-ext_public_subnets

  enable_nat_gateway = true

  tags = merge(
    local.tags,
    {
    }
  )
}

