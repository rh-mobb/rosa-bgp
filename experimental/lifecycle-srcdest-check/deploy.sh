#!/bin/bash
# Deploy ENI source/destination check automation to ROSA cluster
# This script applies the DaemonSet that automatically disables source/destination
# checks on worker node ENIs during lifecycle events.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== ENI Source/Destination Check Automation Deployment ==="
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

IAM_ROLE_ARN=$(terraform output -raw eni_srcdst_iam_role_arn 2>/dev/null)
if [ -z "$IAM_ROLE_ARN" ]; then
    echo "Error: Could not retrieve IAM role ARN from Terraform."
    echo "Please ensure the IAM resources have been created with 'terraform apply'."
    exit 1
fi

AWS_REGION=$(terraform output -raw eni_srcdst_aws_region 2>/dev/null || echo "$AWS_DEFAULT_REGION")
if [ -z "$AWS_REGION" ]; then
if [ -z "$AWS_REGION" ]; then
    echo "Error: Could not determine AWS region."
    echo "Please set AWS_DEFAULT_REGION or ensure terraform outputs include aws_region."
    exit 1
fi

echo "✓ IAM Role ARN: $IAM_ROLE_ARN"
echo "✓ AWS Region: $AWS_REGION"
echo ""

# Apply namespace
echo "Creating namespace..."
oc apply -f "$SCRIPT_DIR/namespace.yaml"
echo "✓ Namespace created"
echo ""

# Apply ServiceAccount with substituted values
echo "Creating ServiceAccount..."
export IAM_ROLE_ARN
export AWS_REGION
envsubst < "$SCRIPT_DIR/serviceaccount.yaml" | oc apply -f -
echo "✓ ServiceAccount created"
echo ""

# Apply DaemonSet with substituted values
echo "Creating DaemonSet..."
envsubst < "$SCRIPT_DIR/daemonset.yaml" | oc apply -f -
echo "✓ DaemonSet created"
echo ""

# Grant hostnetwork SCC
echo "Granting hostnetwork SCC to ServiceAccount..."
oc adm policy add-scc-to-user hostnetwork \
  -z eni-srcdst-disable \
  -n eni-srcdst-disable
echo "✓ SCC granted"
echo ""

# Wait for DaemonSet to be ready
echo "Waiting for DaemonSet pods to start..."
sleep 5

# Verify deployment
echo ""
echo "=== Deployment Status ==="
echo ""
echo "DaemonSet:"
oc get daemonset -n eni-srcdst-disable

echo ""
echo "Pods:"
oc get pods -n eni-srcdst-disable -o wide

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "To verify source/destination check is disabled on worker ENIs:"
echo "1. Get an ENI ID from a worker node:"
echo "   NODE_IP=\$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}')"
echo "   ENI_ID=\$(aws ec2 describe-network-interfaces --filters Name=private-ip-address,Values=\$NODE_IP --query 'NetworkInterfaces[0].NetworkInterfaceId' --output text)"
echo ""
echo "2. Check the SourceDestCheck attribute:"
echo "   aws ec2 describe-network-interfaces --network-interface-ids \$ENI_ID --query 'NetworkInterfaces[0].SourceDestCheck'"
echo ""
echo "Expected result: false"
echo ""

# Check pod logs for any errors
POD_COUNT=$(oc get pods -n eni-srcdst-disable --no-headers 2>/dev/null | wc -l)
if [ "$POD_COUNT" -gt 0 ]; then
    echo "Recent logs from first pod:"
    FIRST_POD=$(oc get pods -n eni-srcdst-disable -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$FIRST_POD" ]; then
        oc logs "$FIRST_POD" -n eni-srcdst-disable -c disable-srcdst 2>/dev/null || echo "(No logs yet or pod still initializing)"
    fi
fi
