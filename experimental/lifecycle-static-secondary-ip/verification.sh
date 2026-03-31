#!/bin/bash
# Verification script for BGP static secondary IP automation
# Checks that secondary IPs are correctly assigned and BGP sessions are working

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== BGP Static Secondary IP Verification ==="
echo ""

# Get AWS region from Terraform
cd "$PROJECT_ROOT"
AWS_REGION=$(terraform output -raw eni_srcdst_aws_region 2>/dev/null || echo "$AWS_DEFAULT_REGION")

if [ -z "$AWS_REGION" ]; then
    echo "Error: Could not determine AWS region."
    exit 1
fi

# Check ConfigMap
echo "1. Checking ConfigMap..."
oc get configmap bgp-static-ip-config -n bgp-static-ip -o yaml
echo ""

# Check DaemonSet
echo "2. Checking DaemonSet..."
oc get daemonset static-ip-agent -n bgp-static-ip
echo ""

# Check Pods
echo "3. Checking Pods..."
oc get pods -n bgp-static-ip -o wide
echo ""

# Check Leases
echo "4. Checking Kubernetes Leases..."
echo "Expected: 3 leases (one per subnet), each with a holder"
for i in 1 2 3; do
  HOLDER=$(oc get lease bgp-static-ip-subnet${i} -n bgp-static-ip -o jsonpath='{.spec.holderIdentity}' 2>/dev/null || echo "NOT FOUND")
  echo "  Subnet ${i}: $HOLDER"
done
echo ""

# Verify IP attachments
echo "5. Verifying secondary IP attachments..."
for i in 1 2 3; do
  echo "Subnet ${i}:"
  EXPECTED_IP=$(oc get cm bgp-static-ip-config -n bgp-static-ip -o jsonpath="{.data.subnet${i}_ip}")
  echo "  Expected IP: $EXPECTED_IP"

  NODE=$(oc get nodes -l bgp_router_subnet=${i} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$NODE" ]; then
    echo "  ❌ No node found with bgp_router_subnet=${i}"
    continue
  fi
  echo "  Node: $NODE"

  NODE_IP=$(oc get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' | awk '{print $1}')
  echo "  Primary IP: $NODE_IP"

  ENI_ID=$(aws ec2 describe-network-interfaces \
    --region $AWS_REGION \
    --filters Name=private-ip-address,Values=$NODE_IP \
    --query 'NetworkInterfaces[0].NetworkInterfaceId' \
    --output text)
  echo "  ENI ID: $ENI_ID"

  IPS=$(aws ec2 describe-network-interfaces \
    --region $AWS_REGION \
    --network-interface-ids $ENI_ID \
    --query 'NetworkInterfaces[0].PrivateIpAddresses[*].PrivateIpAddress' \
    --output text)
  echo "  All IPs: $IPS"

  if echo "$IPS" | grep -q "$EXPECTED_IP"; then
    echo "  ✓ Secondary IP $EXPECTED_IP is attached"
  else
    echo "  ❌ Secondary IP $EXPECTED_IP is NOT attached"
  fi
  echo ""
done

# Check BGP sessions
echo "6. Checking BGP sessions..."
FRR_POD=$(oc get pods -n openshift-frr-k8s -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$FRR_POD" ]; then
  echo "FRR Pod: $FRR_POD"
  echo ""
  oc exec -n openshift-frr-k8s $FRR_POD -c frr -- vtysh -c "show bgp summary" || echo "Could not retrieve BGP summary"
else
  echo "No FRR pods found in openshift-frr-k8s namespace"
fi

echo ""
echo "=== Verification Complete ==="
