# FSx for NetApp ONTAP Resources
# Conditional on var.enable_fsx_ontap (default: false)

# Generate random password for FSx ONTAP SVM admin
resource "random_password" "fsx_ontap_svm_password" {
  count = var.enable_fsx_ontap ? 1 : 0

  length  = 14
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Security Group for FSx ONTAP - allows HTTPS and iSCSI from ROSA worker nodes
resource "aws_security_group" "fsx_ontap_sg" {
  count = var.enable_fsx_ontap ? 1 : 0

  name_prefix = "rosa-virt-fsx-ontap-sg-"
  description = "Security group for FSx ONTAP filesystem - allows HTTPS and iSCSI"
  vpc_id      = module.rosa-vpc.vpc_id

  # HTTPS (NFS over TLS, management API)
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.rosa_worker_fsx_access_sg[0].id]
    description     = "HTTPS from ROSA worker nodes"
  }

  # iSCSI
  ingress {
    from_port       = 3260
    to_port         = 3260
    protocol        = "tcp"
    security_groups = [aws_security_group.rosa_worker_fsx_access_sg[0].id]
    description     = "iSCSI from ROSA worker nodes"
  }

  # NFS (optional - uncomment if needed)
  # ingress {
  #   from_port       = 2049
  #   to_port         = 2049
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.rosa_worker_fsx_access_sg[0].id]
  #   description     = "NFS from ROSA worker nodes"
  # }

  # SMB (optional - uncomment if needed)
  # ingress {
  #   from_port       = 445
  #   to_port         = 445
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.rosa_worker_fsx_access_sg[0].id]
  #   description     = "SMB from ROSA worker nodes"
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(
    local.tags,
    {
      Name = "${var.rosa_cluster_name}-fsx-ontap-SG"
    }
  )
}

# FSx for NetApp ONTAP File System
resource "aws_fsx_ontap_file_system" "rosa_ontap_fs" {
  count = var.enable_fsx_ontap ? 1 : 0

  storage_capacity = 1024 # Minimum: 1024 GiB (1 TiB)
  subnet_ids = [
    module.rosa-vpc.private_subnets[0], # Primary subnet (AZ1)
    module.rosa-vpc.private_subnets[1]  # Standby subnet (AZ2)
  ]
  deployment_type     = "MULTI_AZ_1"
  throughput_capacity = 128 # MB/s - options: 128, 256, 512, 1024, 2048, 4096

  preferred_subnet_id = module.rosa-vpc.private_subnets[0]

  security_group_ids = [aws_security_group.fsx_ontap_sg[0].id]

  # Network configuration
  route_table_ids = module.rosa-vpc.private_route_table_ids

  # Encryption
  kms_key_id = null # Uses AWS-managed key; set to custom KMS key ARN if needed

  # Backup configuration
  automatic_backup_retention_days   = 7
  daily_automatic_backup_start_time = "03:00"   # UTC
  weekly_maintenance_start_time     = "1:04:00" # Sunday 04:00 UTC

  # Performance - using AUTOMATIC mode (no iops value needed)
  # For USER_PROVISIONED mode, add: disk_iops_configuration { mode = "USER_PROVISIONED"; iops = <value> }

  tags = merge(
    local.tags,
    {
      Name = "${var.rosa_cluster_name}-fsx-ontap-fs"
    }
  )
}

# FSx ONTAP Storage Virtual Machine (SVM)
resource "aws_fsx_ontap_storage_virtual_machine" "rosa_svm" {
  count = var.enable_fsx_ontap ? 1 : 0

  file_system_id = aws_fsx_ontap_file_system.rosa_ontap_fs[0].id
  name           = "${var.rosa_cluster_name}-svm"

  # SVM admin authentication
  svm_admin_password = random_password.fsx_ontap_svm_password[0].result

  # Root volume security style
  root_volume_security_style = "UNIX" # or "NTFS", "MIXED"

  tags = merge(
    local.tags,
    {
      Name = "${var.rosa_cluster_name}-fsx-ontap-svm"
    }
  )
}

# FSx ONTAP Outputs
output "fsx_ontap_filesystem_id" {
  description = "FSx for NetApp ONTAP filesystem ID"
  value       = var.enable_fsx_ontap ? aws_fsx_ontap_file_system.rosa_ontap_fs[0].id : null
}

output "fsx_ontap_filesystem_dns_name" {
  description = "FSx for NetApp ONTAP filesystem DNS name"
  value       = var.enable_fsx_ontap ? aws_fsx_ontap_file_system.rosa_ontap_fs[0].dns_name : null
}

output "fsx_ontap_svm_id" {
  description = "FSx ONTAP Storage Virtual Machine ID"
  value       = var.enable_fsx_ontap ? aws_fsx_ontap_storage_virtual_machine.rosa_svm[0].id : null
}

output "fsx_ontap_svm_name" {
  description = "FSx ONTAP Storage Virtual Machine name"
  value       = var.enable_fsx_ontap ? aws_fsx_ontap_storage_virtual_machine.rosa_svm[0].name : null
}

output "fsx_ontap_svm_endpoints" {
  description = "FSx ONTAP SVM endpoints for NFS, SMB, iSCSI, and management"
  value       = var.enable_fsx_ontap ? aws_fsx_ontap_storage_virtual_machine.rosa_svm[0].endpoints : null
}

output "fsx_ontap_svm_management_endpoint" {
  description = "FSx ONTAP SVM management endpoint DNS name"
  value = var.enable_fsx_ontap ? try(
    aws_fsx_ontap_storage_virtual_machine.rosa_svm[0].endpoints[0].management[0].dns_name,
    null
  ) : null
}

output "fsx_ontap_svm_nfs_endpoint" {
  description = "FSx ONTAP SVM NFS endpoint DNS name"
  value = var.enable_fsx_ontap ? try(
    aws_fsx_ontap_storage_virtual_machine.rosa_svm[0].endpoints[0].nfs[0].dns_name,
    null
  ) : null
}

output "fsx_ontap_svm_iscsi_endpoint" {
  description = "FSx ONTAP SVM iSCSI endpoint DNS name"
  value = var.enable_fsx_ontap ? try(
    aws_fsx_ontap_storage_virtual_machine.rosa_svm[0].endpoints[0].iscsi[0].dns_name,
    null
  ) : null
}

output "fsx_ontap_svm_admin_password" {
  description = "FSx ONTAP SVM admin password (sensitive)"
  value       = var.enable_fsx_ontap ? random_password.fsx_ontap_svm_password[0].result : null
  sensitive   = true
}

output "fsx_ontap_security_group_id" {
  description = "Security group ID for FSx ONTAP filesystem"
  value       = var.enable_fsx_ontap ? aws_security_group.fsx_ontap_sg[0].id : null
}
