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
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}
