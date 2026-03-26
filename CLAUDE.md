# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This Terraform project deploys ROSA (Red Hat OpenShift Service on AWS) HCP with **Layer 3 Direct Routing** between the OpenShift Pod Network and AWS VPC networks using BGP and AWS VPC Route Server. This enables non-NATted communication for KubeVirt VMs to be treated as natively routable hosts within the VPC.

### Network Topology

- **Local VPC (vpc1)**: `10.0.0.0/16` - Hosts ROSA cluster and worker nodes
- **Pod Network (CUDN)**: `10.100.0.0/16` - Hosts Pods and KubeVirt VMs
- **External VPC (vpc2)**: `192.168.0.0/16` - External network connected via Transit Gateway

### Key Architecture Components

1. **VPC Route Server**: Dynamically updates subnet route tables via BGP to direct Pod network traffic to ROSA worker nodes
2. **BGP Routing Nodes**: 3 dedicated baremetal worker nodes (1 per AZ) with `bgp_router=true` tag run FRR to advertise routes
3. **High Availability**: Route Server maintains BGP sessions with all 3 routers but only one is active in FIB; failover on BGP keepalive loss
4. **Transit Gateway**: Connects ROSA VPC and External VPC for cross-VPC routing
5. **FRR (Free Range Routing)**: OpenShift frr-k8s operator on router nodes conducts route advertisements

## Common Commands

### Terraform Workflow

```bash
# Initialize and download providers/modules
terraform init

# Plan changes
terraform plan

# Deploy infrastructure (takes 30-40 minutes)
terraform apply

# Show outputs (cluster URLs, passwords, endpoint IPs)
terraform output

# Get specific output value
terraform output -raw rosa_api_url
terraform output -raw rosa_cluster_admin_password

# Destroy all resources
terraform destroy
```

### Prerequisites Check

```bash
# Verify AWS CLI authentication
aws sts get-caller-identity

# Verify ROSA CLI authentication
rosa whoami
```

### OpenShift Cluster Access

```bash
# Login to ROSA cluster (run from terraform directory)
oc login $(terraform output -raw rosa_api_url) -u cluster-admin -p $(terraform output -raw rosa_cluster_admin_password)

# Wait for baremetal router nodes to be ready
watch oc get nodes -l bgp_router=true

# Configure FRR for BGP peering (after nodes are ready)
./oc-cudn-run1.sh

# Apply CUDN and route advertisement configs
oc apply -f yamls/
```

### Inspecting BGP Configuration

```bash
# Check FRR configuration
oc get frrconfiguration -n openshift-frr-k8s

# View route advertisements
oc get routeadvertisements -A

# Check CUDN configuration
oc get userdefinednetworks -A
```

## Configuration Files

### Main Terraform Files

- `providers.tf` - AWS provider with Terraform >= 1.0, AWS provider >= 6.0
- `variables.tf` - Configurable variables (region, CIDR blocks, ASNs, instance types)
- `terraform.tfvars` - User-specific values (must set at minimum: `aws_region`, `owner`)
- `locals.tf` - Common tags applied to all AWS resources

### Infrastructure Files

- `vpc1-rosavpc.tf` - ROSA VPC with 3 AZs, public/private subnets, NAT gateways
- `vpc2-ext.tf` - External VPC for testing cross-VPC routing
- `rosa-cluster.tf` - ROSA HCP cluster module + security groups
- `rosa-pools.tf` - Three machine pools for baremetal router nodes (one per subnet/AZ)
- `vpc1-rs1.tf` - VPC Route Server, endpoints (2 per subnet), and propagation config
- `vpc1-rs1-peers.tf` - BGP peer configuration between Route Server endpoints and router nodes
- `tgw1.tf` - Transit Gateway attachments and static routes

### Helper Scripts

- `scripts/wait_for_instance.sh` - Waits for EC2 instances with specific tags to become available (used as Terraform data source)
- `scripts/disable_src_dst_check.sh` - Disables source/destination checking on router instances (required for routing)
- `oc-cudn-run1.sh` - Configures FRR on router nodes to peer with Route Server endpoints

### OpenShift Configurations

- `yamls/oc-apply-cudn1.yaml` - Creates `cudn1` namespace
- `yamls/oc-apply-cudn2.yaml` - Creates CUDN `cluster-udn-prod` with `10.100.0.0/16` subnet
- `yamls/oc-apply-cudn3.yaml` - Creates route advertisement for CUDN

## Important Details

### BGP Configuration

- **ROSA ASN**: Configurable via `rosa_bgp_asn` (default: `65001`)
- **Route Server ASN**: Configurable via `rs_amazon_side_asn` (default: `65000`)
- **Peering**: Each router node peers with 2 Route Server endpoints in its subnet (6 total BGP sessions per node)
- **Liveness Detection**: Uses `bgp-keepalive` (BFD not working)

### Router Node Requirements

- **Instance Type**: Baremetal (`c5.metal` default) required for proper routing performance
- **Tags**: Nodes tagged with `bgp_router=true` and `bgp_router_subnet={1-3}`
- **Source/Dest Check**: Must be disabled (handled by `disable_src_dst_check.sh`)
- **Security Groups**: Two SGs attached - one allowing RFC1918, one allowing all (for IGW traffic)
- **Placement**: One node per private subnet/AZ for redundancy

### Deployment Dependencies

The deployment has critical ordering:
1. VPCs and Route Server must exist before ROSA cluster
2. ROSA cluster and machine pools must be created before BGP peers (needs instance IPs)
3. `wait_for_instance.sh` script polls for instances to get their private IPs
4. FRR configuration (`oc-cudn-run1.sh`) requires cluster to be accessible and waits 60s for `openshift-frr-k8s` namespace

### Static Route Server Endpoints

Note: `vpc1-rs1.tf` currently uses static resource definitions for 3 subnets (6 endpoints total). Comment indicates this should be converted to `for_each` loop for better scalability.

### Transit Gateway Routes

- TGW routes are configured with `transit_gateway_default_route_table_association = false` and `transit_gateway_default_route_table_propagation = false`
- Static routes added to both VPC route tables for cross-VPC communication
- CUDN prefix `10.100.0.0/16` is explicitly routed through TGW to external VPC

## Customization

### Key Variables to Configure

In `terraform.tfvars`:
- `aws_region` - AWS region for deployment
- `owner` - Used in resource names and tags
- `project_id` - Optional suffix for resource names
- `rosa_cluster_name` - Name of ROSA cluster
- `rosa_openshift_version` - OpenShift version
- `rosa_compute_instance_type` - Instance type for router nodes (must be baremetal)
- `rosa_bgp_asn` - BGP AS number for ROSA side
- `rs_amazon_side_asn` - BGP AS number for Route Server
- VPC CIDR blocks and subnet ranges for both VPCs

### Adding More Router Nodes

To add nodes in additional AZs:
1. Add subnet to VPC module in `vpc1-rosavpc.tf`
2. Create new machine pool module in `rosa-pools.tf`
3. Add Route Server endpoints in `vpc1-rs1.tf`
4. Add BGP peer resources in `vpc1-rs1-peers.tf`
5. Update `oc-cudn-run1.sh` to include new endpoint IPs

## Common Issues

- **FRR namespace not available**: Wait longer before running `oc-cudn-run1.sh` or re-run the script
- **BGP sessions not establishing**: Verify source/destination check is disabled on router instances
- **Routing not working**: Check Route Server propagation is enabled for all route tables
- **Long deployment time**: Expected 30-40 minutes due to ROSA cluster creation and node provisioning

## Commit Message Guidelines

This project follows specific guidelines for marking AI-generated or AI-assisted content in commits:

- **Use `Assisted-by:`** when a human has reviewed, modified, or directed AI output
- **Use `Generated-by:`** when code has been produced by AI without significant human input or intervention
- Include the specific AI tool used (e.g., "Claude Code (Claude Sonnet 4.5)")

Example:
```
Add OpenShift Virtualization automation

Automated installation of kubevirt-hyperconverged operator with
wait/verification logic for production readiness.

Assisted-by: Claude Code (Claude Sonnet 4.5)
```
