# IAM resources for ENI source/destination check automation
# This allows a DaemonSet running in the ROSA cluster to disable source/destination
# checks on worker node ENIs automatically during lifecycle events.

# Data source to get OIDC provider ARN from the ROSA cluster
# The ROSA HCP module creates the OIDC provider automatically
data "aws_iam_openid_connect_provider" "rosa_oidc" {
  url = "https://${module.hcp.oidc_endpoint_url}"
}

# IAM Policy: Allow modifying network interface attributes for cluster-owned ENIs
resource "aws_iam_policy" "eni_srcdst_disable" {
  name        = "${var.rosa_cluster_name}-eni-srcdst-disable"
  description = "Allow disabling source/destination check on ROSA worker ENIs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:ModifyNetworkInterfaceAttribute"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/kubernetes.io/cluster/${module.hcp.cluster_id}" = "owned"
          }
        }
      }
    ]
  })

  tags = merge(
    local.tags,
    {
      Name = "${var.rosa_cluster_name}-eni-srcdst-disable-policy"
    }
  )
}

# IAM Role: Allow the ServiceAccount to assume this role via OIDC
resource "aws_iam_role" "eni_srcdst_disable" {
  name        = "${var.rosa_cluster_name}-eni-srcdst-disable"
  description = "Role for ROSA DaemonSet to disable ENI source/destination checks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.rosa_oidc.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${trimprefix(data.aws_iam_openid_connect_provider.rosa_oidc.url, "https://")}:sub" = "system:serviceaccount:eni-srcdst-disable:eni-srcdst-disable"
            "${trimprefix(data.aws_iam_openid_connect_provider.rosa_oidc.url, "https://")}:aud" = "openshift"
          }
        }
      }
    ]
  })

  tags = merge(
    local.tags,
    {
      Name = "${var.rosa_cluster_name}-eni-srcdst-disable-role"
    }
  )
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "eni_srcdst_disable" {
  role       = aws_iam_role.eni_srcdst_disable.name
  policy_arn = aws_iam_policy.eni_srcdst_disable.arn
}

# Outputs for use in deployment scripts
output "eni_srcdst_iam_role_arn" {
  description = "ARN of the IAM role for ENI source/destination check automation"
  value       = aws_iam_role.eni_srcdst_disable.arn
}

output "eni_srcdst_iam_policy_arn" {
  description = "ARN of the IAM policy for ENI source/destination check automation"
  value       = aws_iam_policy.eni_srcdst_disable.arn
}

output "eni_srcdst_aws_region" {
  description = "AWS region for ENI source/destination check automation"
  value       = var.aws_region
}

# IAM resources for BGP static secondary IP management
# This allows a DaemonSet to assign/unassign secondary IPs to router node ENIs

# IAM Policy: Allow assigning/unassigning secondary IPs to cluster-owned ENIs
resource "aws_iam_policy" "bgp_static_ip_attach" {
  name        = "${var.rosa_cluster_name}-bgp-static-ip-attach"
  description = "Allow BGP controller to assign/unassign secondary IPs to worker node ENIs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow describe operations (needed to check current IPs)
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        # Allow assign/unassign operations, scoped to cluster-owned ENIs
        Effect = "Allow"
        Action = [
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            # Scope to ENIs owned by this cluster
            "ec2:ResourceTag/kubernetes.io/cluster/${module.hcp.cluster_id}" = "owned"
          }
        }
      }
    ]
  })

  tags = merge(
    local.tags,
    {
      Name = "${var.rosa_cluster_name}-bgp-static-ip-attach-policy"
    }
  )
}

# IAM Role: Allow the ServiceAccount to assume this role via OIDC
resource "aws_iam_role" "bgp_static_ip" {
  name        = "${var.rosa_cluster_name}-bgp-static-ip"
  description = "Role for BGP static IP controller to manage node ENI secondary IPs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.rosa_oidc.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${trimprefix(data.aws_iam_openid_connect_provider.rosa_oidc.url, "https://")}:sub" = "system:serviceaccount:bgp-static-ip:bgp-static-ip"
            "${trimprefix(data.aws_iam_openid_connect_provider.rosa_oidc.url, "https://")}:aud" = "openshift"
          }
        }
      }
    ]
  })

  tags = merge(
    local.tags,
    {
      Name = "${var.rosa_cluster_name}-bgp-static-ip-role"
    }
  )
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "bgp_static_ip_attach" {
  role       = aws_iam_role.bgp_static_ip.name
  policy_arn = aws_iam_policy.bgp_static_ip_attach.arn
}

# Output for use in deployment scripts
output "bgp_static_ip_role_arn" {
  description = "ARN of IAM role for BGP static secondary IP controller"
  value       = aws_iam_role.bgp_static_ip.arn
}
