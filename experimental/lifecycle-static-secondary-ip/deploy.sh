#!/bin/bash
# Deploy BGP static secondary IP automation to ROSA cluster
# This script applies the DaemonSet that automatically assigns static secondary IPs
# to BGP router node ENIs using Kubernetes Lease-based leader election.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== BGP Static Secondary IP Automation Deployment ==="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check if oc is available and logged in
if ! command -v oc &> /dev/null; then
    echo "Error: oc command not found. Please install the OpenShift CLI."
    exit 1
fi

if ! oc whoami &> /dev/null; then
    echo "Error: Not logged into OpenShift cluster. Please run 'oc login' first."
    exit 1
fi

echo "✓ Logged into OpenShift cluster as: $(oc whoami)"

# Check if terraform state exists
if [ ! -f "$PROJECT_ROOT/terraform.tfstate" ]; then
    echo "Error: Terraform state not found. Please run 'terraform apply' first."
    exit 1
fi

echo "✓ Terraform state found"
echo ""

# Get values from Terraform outputs
echo "Retrieving configuration from Terraform outputs..."
cd "$PROJECT_ROOT"

IAM_ROLE_ARN=$(terraform output -raw bgp_static_ip_role_arn 2>/dev/null)
if [ -z "$IAM_ROLE_ARN" ]; then
    echo "Error: Could not retrieve IAM role ARN from Terraform."
    echo "Please ensure the IAM resources have been created with 'terraform apply'."
    exit 1
fi

SUBNET1_IP=$(terraform output -raw bgp_secondary_ip_subnet1 2>/dev/null)
SUBNET2_IP=$(terraform output -raw bgp_secondary_ip_subnet2 2>/dev/null)
SUBNET3_IP=$(terraform output -raw bgp_secondary_ip_subnet3 2>/dev/null)
AWS_REGION=$(terraform output -raw eni_srcdst_aws_region 2>/dev/null || echo "$AWS_DEFAULT_REGION")

if [ -z "$SUBNET1_IP" ] || [ -z "$SUBNET2_IP" ] || [ -z "$SUBNET3_IP" ]; then
    echo "Error: Could not retrieve secondary IP addresses from Terraform."
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo "Error: Could not determine AWS region."
    echo "Please set AWS_DEFAULT_REGION or ensure terraform outputs include aws_region."
    exit 1
fi

echo "✓ IAM Role ARN: $IAM_ROLE_ARN"
echo "✓ AWS Region: $AWS_REGION"
echo "✓ Static IPs: $SUBNET1_IP, $SUBNET2_IP, $SUBNET3_IP"
echo ""

# Apply namespace
echo "Creating namespace..."
oc apply -f "$SCRIPT_DIR/namespace.yaml"
echo "✓ Namespace created"
echo ""

# Create ConfigMap with secondary IP configuration
echo "Creating ConfigMap..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: bgp-static-ip-config
  namespace: bgp-static-ip
data:
  subnet1_ip: "${SUBNET1_IP}"
  subnet2_ip: "${SUBNET2_IP}"
  subnet3_ip: "${SUBNET3_IP}"
  aws_region: "${AWS_REGION}"
EOF
echo "✓ ConfigMap created"
echo ""

# Apply ServiceAccount with substituted values
echo "Creating ServiceAccount..."
export IAM_ROLE_ARN
export AWS_REGION
envsubst '$IAM_ROLE_ARN $AWS_REGION' < "$SCRIPT_DIR/serviceaccount.yaml" | oc apply -f -
echo "✓ ServiceAccount created"
echo ""

# Apply RBAC
echo "Creating RBAC..."
oc apply -f "$SCRIPT_DIR/rbac.yaml"
echo "✓ RBAC created"
echo ""

# Apply DaemonSet with substituted values
echo "Creating DaemonSet..."
envsubst '$AWS_REGION' < "$SCRIPT_DIR/daemonset.yaml" | oc apply -f -
echo "✓ DaemonSet created"
echo ""

# Grant hostnetwork SCC
echo "Granting hostnetwork SCC to ServiceAccount..."
oc adm policy add-scc-to-user hostnetwork \
  -z bgp-static-ip \
  -n bgp-static-ip
echo "✓ SCC granted"
echo ""

# Wait for DaemonSet pods to start
echo "Waiting for DaemonSet pods to start..."
sleep 10

# Verify deployment
echo ""
echo "=== Deployment Status ==="
echo ""
echo "DaemonSet:"
oc get daemonset -n bgp-static-ip

echo ""
echo "Pods:"
oc get pods -n bgp-static-ip -o wide

echo ""
echo "ConfigMap:"
oc get configmap bgp-static-ip-config -n bgp-static-ip

echo ""
echo "=== Deployment Complete ===\"
echo ""
echo "To verify static secondary IPs are being assigned:"
echo "1. Check pod logs:"
echo "   oc logs -n bgp-static-ip -l app=static-ip-agent -f"
echo ""
echo "2. Check Kubernetes Leases (should have 3, one per subnet):"
echo "   oc get leases -n bgp-static-ip"
echo ""
echo "3. Verify IPs attached to ENIs:"
echo "   for i in 1 2 3; do"
echo "     NODE_IP=\\$(oc get nodes -l bgp_router_subnet=\\$i -o jsonpath='{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}')"
echo "     ENI_ID=\\$(aws ec2 describe-network-interfaces --region $AWS_REGION --filters Name=private-ip-address,Values=\\$NODE_IP --query 'NetworkInterfaces[0].NetworkInterfaceId' --output text)"
echo "     echo \"Subnet \\$i ENI \\$ENI_ID:\""
echo "     aws ec2 describe-network-interfaces --region $AWS_REGION --network-interface-ids \\$ENI_ID --query 'NetworkInterfaces[0].PrivateIpAddresses[*].PrivateIpAddress'"
echo "   done"
echo ""

# Check pod logs for any errors
POD_COUNT=$(oc get pods -n bgp-static-ip --no-headers 2>/dev/null | wc -l)
if [ "$POD_COUNT" -gt 0 ]; then
    echo "Recent logs from first pod:"
    FIRST_POD=$(oc get pods -n bgp-static-ip -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$FIRST_POD" ]; then
        oc logs "$FIRST_POD" -n bgp-static-ip --tail=20 2>/dev/null || echo "(No logs yet or pod still initializing)"
    fi
fi
echo ""
