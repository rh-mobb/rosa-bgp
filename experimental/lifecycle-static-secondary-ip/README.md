# BGP Static Secondary IP Automation

This directory contains automation for assigning static secondary IPs to BGP router nodes in ROSA HCP clusters. This solves the problem of BGP peering failures when worker nodes are replaced during rolling updates or failures.

## Problem Statement

BGP router nodes peer with AWS Route Server using their private IPs. When nodes are replaced, they receive new IPs, but Route Server BGP peer configuration still references old IPs, breaking BGP connectivity.

**Solution**: Pre-allocate static secondary IPs and automatically assign them to router nodes using Kubernetes Lease-based leader election.

## Architecture

### Components

1. **Terraform** (`vpc1-bgp-secondary-ips.tf`, `eni-srcdst-iam.tf`):
   - Creates 3 CIDR reservations for static IPs (10.0.1.10, 10.0.2.10, 10.0.3.10)
   - Updates Route Server BGP peers to use static IPs
   - Creates IAM policy + role for secondary IP management

2. **Kubernetes DaemonSet** (`daemonset.yaml`):
   - Runs on BGP router nodes (nodeSelector: `bgp_router: "true"`)
   - Uses Kubernetes Leases for leader election (one lease per subnet)
   - Leader node assigns secondary IP to its ENI
   - Non-leader nodes ensure IP is detached

3. **Lease-Based Coordination**:
   - 3 Leases: `bgp-static-ip-subnet1`, `bgp-static-ip-subnet2`, `bgp-static-ip-subnet3`
   - Lease duration: 60 seconds
   - Renewal interval: 15 seconds
   - Prevents split-brain and race conditions

## FRR Compatibility

**Phase 0 Test Results**: FRR does not require configuration changes for secondary IPs.

- BGP sessions remain established when secondary IPs are attached
- FRR continues using primary IP as source for BGP traffic
- No FRRConfiguration modifications needed

## Prerequisites

- ROSA HCP cluster deployed via Terraform
- Terraform >= 1.0, AWS provider >= 6.0
- `oc` CLI installed and logged into cluster
- AWS CLI configured with valid credentials

## Installation

### 1. Deploy Terraform Infrastructure

From project root:

```bash
terraform apply
```

This creates:
- 3 CIDR reservations for static IPs
- IAM policy allowing AssignPrivateIpAddresses/UnassignPrivateIpAddresses
- IAM role with OIDC trust for ServiceAccount `bgp-static-ip`
- Route Server BGP peers configured with static IPs (replaces dynamic IP discovery)

### 2. Log into ROSA Cluster

```bash
oc login $(terraform output -raw rosa_api_url) \
  -u cluster-admin \
  -p $(terraform output -raw rosa_cluster_admin_password)
```

### 3. Deploy Static IP Controller

Run the automated deployment script:

```bash
./experimental/lifecycle-static-secondary-ip/deploy.sh
```

The script automatically:
1. Validates prerequisites (oc login, terraform state)
2. Retrieves IAM role ARN and secondary IPs from Terraform outputs
3. Creates namespace with privileged Pod Security labels
4. Creates ConfigMap with IP allocations
5. Applies ServiceAccount (with IRSA annotation), RBAC, DaemonSet
6. Grants `hostnetwork` SCC to ServiceAccount
7. Displays deployment status and verification instructions

## Verification

### Quick Check

```bash
./experimental/lifecycle-static-secondary-ip/verification.sh
```

This checks:
- ConfigMap configuration
- DaemonSet and pod status
- Kubernetes Leases (3 leases, each with a holder)
- Secondary IPs attached to correct ENIs
- BGP session status

### Manual Verification

**Check DaemonSet Status:**
```bash
oc get daemonset -n bgp-static-ip
oc get pods -n bgp-static-ip -o wide
```

Expected: 3 running pods (one per BGP router node)

**Check Leases:**
```bash
oc get leases -n bgp-static-ip
```

Expected: 3 leases (`bgp-static-ip-subnet1`, `bgp-static-ip-subnet2`, `bgp-static-ip-subnet3`), each showing a `holderIdentity`

**Check Pod Logs:**
```bash
oc logs -n bgp-static-ip -l app=static-ip-agent -f
```

Expected: Logs showing leader election and secondary IP assignment

**Verify ENI Secondary IPs:**
```bash
# For each subnet
NODE_IP=$(oc get nodes -l bgp_router_subnet=1 -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
ENI_ID=$(aws ec2 describe-network-interfaces --region us-east-2 --filters Name=private-ip-address,Values=$NODE_IP --query 'NetworkInterfaces[0].NetworkInterfaceId' --output text)
aws ec2 describe-network-interfaces --region us-east-2 --network-interface-ids $ENI_ID --query 'NetworkInterfaces[0].PrivateIpAddresses[*].PrivateIpAddress'
```

Expected: Both primary IP and secondary IP (10.0.1.10) shown

**Check BGP Sessions:**
```bash
oc exec -n openshift-frr-k8s <frr-pod> -c frr -- vtysh -c "show bgp summary"
```

Expected: BGP sessions with Route Server endpoints in "Established" state

## Testing Scenarios

### Node Replacement (Rolling Update)

1. Drain a BGP router node:
   ```bash
   oc adm drain <node-name> --ignore-daemonsets --delete-emptydir-data
   ```

2. Wait for replacement node to join cluster

3. Verify:
   - New node acquires lease for its subnet
   - Secondary IP is reassigned to new node's ENI
   - BGP sessions re-establish automatically

### AZ-Wide Failure Simulation

1. Terminate all nodes in one subnet (e.g., using AWS console)

2. Wait for replacement nodes

3. Verify:
   - First recovered node acquires lease
   - Secondary IP assigned to recovered node
   - BGP peering restores

## Files

- `namespace.yaml` - Namespace with privileged Pod Security labels
- `serviceaccount.yaml` - ServiceAccount with IRSA annotation (templated)
- `rbac.yaml` - Role + RoleBinding for Lease management
- `daemonset.yaml` - DaemonSet running static IP agent (templated)
- `deploy.sh` - Automated deployment script
- `verification.sh` - Verification script
- `README.md` - This file

## Troubleshooting

**Pods in CrashLoopBackOff:**
- Check IAM role ARN is correct: `oc get sa bgp-static-ip -n bgp-static-ip -o yaml`
- Verify IRSA pod identity webhook injected credentials: `oc exec -n bgp-static-ip <pod> -- env | grep AWS`

**Lease Conflicts:**
- Check lease status: `oc get lease bgp-static-ip-subnet1 -n bgp-static-ip -o yaml`
- Verify only one node per subnet: `oc get nodes -l bgp_router=true`

**Secondary IP Not Attached:**
- Check pod logs: `oc logs -n bgp-static-ip <pod>`
- Verify IAM permissions: AWS policy allows `ec2:AssignPrivateIpAddresses`
- Confirm CIDR reservations exist: `terraform state list | grep cidr_reservation`

**BGP Sessions Not Established:**
- Verify Route Server peers configured with static IPs: `terraform output | grep bgp_secondary_ip`
- Check FRR configuration: `oc get frrconfiguration -n openshift-frr-k8s`
- Review Route Server peer status in AWS console

## Rollback

If issues occur:

```bash
# 1. Delete DaemonSet
oc delete daemonset static-ip-agent -n bgp-static-ip

# 2. Manually detach secondary IPs
for i in 1 2 3; do
  IP=$(terraform output -raw bgp_secondary_ip_subnet${i})
  # Find and unassign from ENIs
  aws ec2 unassign-private-ip-addresses --region <region> --network-interface-id <eni> --private-ip-addresses ${IP}
done

# 3. Delete Kubernetes resources
oc delete namespace bgp-static-ip

# 4. Revert Terraform changes
git checkout HEAD -- vpc1-rs1-peers.tf vpc1-bgp-secondary-ips.tf eni-srcdst-iam.tf
terraform apply
```

## Security Considerations

- IAM policy scoped to ENIs tagged with `kubernetes.io/cluster/<cluster-id>=owned`
- ServiceAccount uses IRSA (no static credentials)
- DaemonSet runs with `hostNetwork: true` (required for IMDS access)
- Requires `hostnetwork` SCC (explicitly granted)
- Kubernetes Leases prevent split-brain scenarios

## Future Enhancements

- [ ] Metrics/monitoring integration (Prometheus)
- [ ] Alerting on lease acquisition failures
- [ ] Support for dynamic number of subnets/AZs
- [ ] Automated testing framework
- [ ] Multi-cluster support
