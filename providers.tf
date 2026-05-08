provider "aws" {
  region = var.aws_region
  default_tags { tags = local.tags }
  ignore_tags {
    # ignore tags added by ROSA to subnets
    key_prefixes = ["kubernetes.io/cluster/"]
  }
}

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "= 8.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aviatrix" {
  controller_ip = var.avx_controller_public_ip
  username      = var.avx_username
  password      = var.avx_controller_admin_password
}
