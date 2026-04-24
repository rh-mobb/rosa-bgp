#!/bin/bash
# Setup SSH access for test VMs
# Generates an SSH keypair and stores it as Kubernetes secrets

set -e

KEYFILE="tests/test-vm-key"
TEMPLATE_FILE="tests/setup/templates/vm-template.yaml"
JUMP_POD_TEMPLATE="tests/setup/templates/jump-pod-template.yaml"

# Generate jump pod YAML from template
# Usage: generate_jump_pod_yaml <pod_name> <namespace>
generate_jump_pod_yaml() {
    local pod_name=$1
    local namespace=$2

    # Export variables for envsubst
    export POD_NAME="$pod_name"
    export POD_NAMESPACE="$namespace"

    # Generate YAML from template
    envsubst < "$JUMP_POD_TEMPLATE"
}

# Generate VM YAML from template
# Usage: generate_vm_yaml <vm_name> <namespace> <html_content> <affinity_type> [target_vm] [target_namespace]
# affinity_type: "none", "same-node", "different-node"
# target_vm: VM name to use for pod affinity/anti-affinity (required for same-node/different-node)
# target_namespace: Namespace of target VM (defaults to same as vm namespace)
generate_vm_yaml() {
    local vm_name=$1
    local namespace=$2
    local html_content=$3
    local affinity_type=$4
    local target_vm=$5
    local target_namespace=${6:-$namespace}

    # Quote HTML content for YAML
    html_content="${html_content//\"/\\\"}"

    # Generate affinity YAML based on type
    local affinity_yaml=""
    local affinity_kind=""

    case "$affinity_type" in
        "same-node")
            affinity_kind="podAffinity"
            ;;
        "different-node")
            affinity_kind="podAntiAffinity"
            ;;
        *)
            affinity_kind=""
            ;;
    esac

    if [ -n "$affinity_kind" ]; then
        # Add namespaces field if target is in a different namespace
        local namespaces_yaml=""
        if [ "$target_namespace" != "$namespace" ]; then
            namespaces_yaml="
            namespaces:
            - $target_namespace"
        fi

        affinity_yaml="      affinity:
        $affinity_kind:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: kubevirt.io/vm
                operator: In
                values:
                - $target_vm$namespaces_yaml
            topologyKey: kubernetes.io/hostname"
    fi

    # Export variables for envsubst
    export VM_NAME="$vm_name"
    export VM_NAMESPACE="$namespace"
    export SSH_PUBKEY="$PUBKEY"
    export HTML_CONTENT="$html_content"
    export AFFINITY_YAML="$affinity_yaml"

    # Generate YAML from template
    envsubst < "$TEMPLATE_FILE"
}

echo "==================================================================="
echo "Setting up SSH access for test VMs"
echo "==================================================================="
echo

# Generate SSH keypair if it doesn't exist
if [ ! -f "$KEYFILE" ]; then
    echo "Generating new SSH keypair..."
    ssh-keygen -t ed25519 -f "$KEYFILE" -N '' -C 'test-vm-access'
    echo "✓ Keypair generated: $KEYFILE"
else
    echo "✓ Using existing keypair: $KEYFILE"
fi

# Read the public key
PUBKEY=$(cat ${KEYFILE}.pub)
echo
echo "Public key: $PUBKEY"
echo

# Create SSH key secrets in both namespaces
echo "Creating SSH key secrets in namespaces..."
for namespace in cudn1 cudn2; do
    oc create secret generic test-vm-ssh-key \
        --from-file=id_ed25519="$KEYFILE" \
        --from-file=id_ed25519.pub="${KEYFILE}.pub" \
        --namespace="$namespace" \
        --dry-run=client -o yaml | oc apply -f -
    echo "✓ Secret created/updated in $namespace"
done
echo

# Update test-vm-a.yaml
echo "Updating test-vm-a.yaml..."
generate_vm_yaml \
    "test-vm-a" \
    "cudn1" \
    "<h1>Test VM A - CUDN1</h1><p>Network: cluster-udn-prod (10.100.0.0/16)</p><p>IP: \$(hostname -I)</p>" \
    "none" \
    > tests/test-vm-a.yaml
echo "✓ test-vm-a.yaml created"

# Update test-vm-b.yaml
echo "Updating test-vm-b.yaml..."
generate_vm_yaml \
    "test-vm-b" \
    "cudn2" \
    "<h1>Test VM B - CUDN2</h1><p>Network: cluster-udn-second (10.101.0.0/16)</p><p>IP: \$(hostname -I)</p>" \
    "none" \
    > tests/test-vm-b.yaml
echo "✓ test-vm-b.yaml created"

echo "✓ VM configurations updated"
echo

# Delete existing VMs
echo "Deleting existing VMs..."
oc delete vm test-vm-a -n cudn1 --ignore-not-found=true
oc delete vm test-vm-a-sameworker -n cudn1 --ignore-not-found=true
oc delete vm test-vm-a-differentworker -n cudn1 --ignore-not-found=true
oc delete vm test-vm-b -n cudn2 --ignore-not-found=true
oc delete vm test-vm-b-sameworker-as-a -n cudn2 --ignore-not-found=true
oc delete vm test-vm-b-differentworker-as-a -n cudn2 --ignore-not-found=true
echo "✓ VMs deleted"
echo

# Wait a moment for cleanup
sleep 5

# Apply new VM configurations
echo "Creating VMs with SSH keys..."
oc apply -f tests/test-vm-a.yaml
oc apply -f tests/test-vm-b.yaml
echo "✓ test-vm-a and test-vm-b created"
echo

# Wait for test-vm-a to be running
echo "Waiting for test-vm-a to be running..."
oc wait --for=condition=Ready vmi/test-vm-a -n cudn1 --timeout=300s
echo "✓ test-vm-a is running"
echo

# Create test-vm-a-sameworker on the same node as test-vm-a
echo "Updating test-vm-a-sameworker.yaml..."
generate_vm_yaml \
    "test-vm-a-sameworker" \
    "cudn1" \
    "<h1>Test VM A2 - CUDN1</h1><p>Network: cluster-udn-prod (10.100.0.0/16)</p><p>IP: \$(hostname -I)</p>" \
    "same-node" \
    "test-vm-a" \
    > tests/test-vm-a-sameworker.yaml
echo "✓ test-vm-a-sameworker.yaml created"

# Apply test-vm-a-sameworker
echo "Creating test-vm-a-sameworker on same node as test-vm-a..."
oc apply -f tests/test-vm-a-sameworker.yaml
echo "✓ test-vm-a-sameworker created"
echo

# Create test-vm-a-differentworker on a different node than test-vm-a
echo "Updating test-vm-a-differentworker.yaml..."
generate_vm_yaml \
    "test-vm-a-differentworker" \
    "cudn1" \
    "<h1>Test VM A Different Worker - CUDN1</h1><p>Network: cluster-udn-prod (10.100.0.0/16)</p><p>IP: \$(hostname -I)</p>" \
    "different-node" \
    "test-vm-a" \
    > tests/test-vm-a-differentworker.yaml
echo "✓ test-vm-a-differentworker.yaml created"

# Apply test-vm-a-differentworker
echo "Creating test-vm-a-differentworker on different node than test-vm-a..."
oc apply -f tests/test-vm-a-differentworker.yaml
echo "✓ test-vm-a-differentworker created"
echo

# Create test-vm-b-sameworker-as-a on the same node as test-vm-a (for isolation testing)
echo "Updating test-vm-b-sameworker-as-a.yaml..."
generate_vm_yaml \
    "test-vm-b-sameworker-as-a" \
    "cudn2" \
    "<h1>Test VM B Same Worker as A - CUDN2</h1><p>Network: cluster-udn-second (10.101.0.0/16)</p><p>IP: \$(hostname -I)</p>" \
    "same-node" \
    "test-vm-a" \
    "cudn1" \
    > tests/test-vm-b-sameworker-as-a.yaml
echo "✓ test-vm-b-sameworker-as-a.yaml created"

# Apply test-vm-b-sameworker-as-a
echo "Creating test-vm-b-sameworker-as-a on same node as test-vm-a (for CUDN isolation testing)..."
oc apply -f tests/test-vm-b-sameworker-as-a.yaml
echo "✓ test-vm-b-sameworker-as-a created"
echo

# Create test-vm-b-differentworker-as-a on a different node than test-vm-a (for isolation testing)
echo "Updating test-vm-b-differentworker-as-a.yaml..."
generate_vm_yaml \
    "test-vm-b-differentworker-as-a" \
    "cudn2" \
    "<h1>Test VM B Different Worker than A - CUDN2</h1><p>Network: cluster-udn-second (10.101.0.0/16)</p><p>IP: \$(hostname -I)</p>" \
    "different-node" \
    "test-vm-a" \
    "cudn1" \
    > tests/test-vm-b-differentworker-as-a.yaml
echo "✓ test-vm-b-differentworker-as-a.yaml created"

# Apply test-vm-b-differentworker-as-a
echo "Creating test-vm-b-differentworker-as-a on different node than test-vm-a (for CUDN isolation testing)..."
oc apply -f tests/test-vm-b-differentworker-as-a.yaml
echo "✓ test-vm-b-differentworker-as-a created"
echo

# Create jump pods for SSH access
echo "Creating jump pods for test infrastructure..."
for namespace in cudn1 cudn2; do
    pod_name="network-jump"
    [ "$namespace" = "cudn2" ] && pod_name="network-jump-cudn2"

    generate_jump_pod_yaml "$pod_name" "$namespace" | oc apply -f - >/dev/null
    echo "✓ Jump pod created in $namespace"
done

# Wait for jump pods to be ready
echo "Waiting for jump pods to be ready..."
oc wait --for=condition=Ready pod/network-jump -n cudn1 --timeout=60s >/dev/null 2>&1
oc wait --for=condition=Ready pod/network-jump-cudn2 -n cudn2 --timeout=60s >/dev/null 2>&1
echo "✓ Jump pods ready"
echo

echo "==================================================================="
echo "Waiting for all VMs to be ready..."
echo "==================================================================="
echo
echo "Waiting for all VMs..."
oc wait --for=condition=Ready vmi/test-vm-a-sameworker -n cudn1 --timeout=300s >/dev/null 2>&1
oc wait --for=condition=Ready vmi/test-vm-a-differentworker -n cudn1 --timeout=300s >/dev/null 2>&1
oc wait --for=condition=Ready vmi/test-vm-b -n cudn2 --timeout=300s >/dev/null 2>&1
oc wait --for=condition=Ready vmi/test-vm-b-sameworker-as-a -n cudn2 --timeout=300s >/dev/null 2>&1
oc wait --for=condition=Ready vmi/test-vm-b-differentworker-as-a -n cudn2 --timeout=300s >/dev/null 2>&1
echo "✓ All VMs are ready"
echo

# Verify node placement
VM_A_NODE_FINAL=$(oc get vmi test-vm-a -n cudn1 -o jsonpath='{.status.nodeName}')
VM_A_SAMEWORKER_NODE=$(oc get vmi test-vm-a-sameworker -n cudn1 -o jsonpath='{.status.nodeName}')
VM_A_DIFFERENTWORKER_NODE=$(oc get vmi test-vm-a-differentworker -n cudn1 -o jsonpath='{.status.nodeName}')
VM_B_NODE=$(oc get vmi test-vm-b -n cudn2 -o jsonpath='{.status.nodeName}')
VM_B_SAMEWORKER_AS_A_NODE=$(oc get vmi test-vm-b-sameworker-as-a -n cudn2 -o jsonpath='{.status.nodeName}')
VM_B_DIFFERENTWORKER_AS_A_NODE=$(oc get vmi test-vm-b-differentworker-as-a -n cudn2 -o jsonpath='{.status.nodeName}')

echo "==================================================================="
echo "Setup complete!"
echo "==================================================================="
echo
echo "SSH private key: $KEYFILE"
echo "SSH public key: ${KEYFILE}.pub"
echo
echo "Infrastructure created:"
echo "  - SSH key secrets in cudn1 and cudn2 namespaces"
echo "  - Jump pods (network-jump) for test SSH access"
echo "  - Test VMs:"
echo "    - test-vm-a (cudn1) on node: $VM_A_NODE_FINAL"
echo "    - test-vm-a-sameworker (cudn1) on node: $VM_A_SAMEWORKER_NODE"
echo "    - test-vm-a-differentworker (cudn1) on node: $VM_A_DIFFERENTWORKER_NODE"
echo "    - test-vm-b (cudn2) on node: $VM_B_NODE"
echo "    - test-vm-b-sameworker-as-a (cudn2) on node: $VM_B_SAMEWORKER_AS_A_NODE"
echo "    - test-vm-b-differentworker-as-a (cudn2) on node: $VM_B_DIFFERENTWORKER_AS_A_NODE"
echo

if [ "$VM_A_NODE_FINAL" = "$VM_A_SAMEWORKER_NODE" ]; then
    echo "✓ test-vm-a and test-vm-a-sameworker are on the same node"
else
    echo "⚠ WARNING: test-vm-a and test-vm-a-sameworker are on different nodes!"
fi

if [ "$VM_A_NODE_FINAL" != "$VM_A_DIFFERENTWORKER_NODE" ]; then
    echo "✓ test-vm-a and test-vm-a-differentworker are on different nodes"
else
    echo "⚠ WARNING: test-vm-a and test-vm-a-differentworker are on the same node!"
fi

if [ "$VM_A_NODE_FINAL" = "$VM_B_SAMEWORKER_AS_A_NODE" ]; then
    echo "✓ test-vm-a and test-vm-b-sameworker-as-a are on the same node (for CUDN isolation testing)"
else
    echo "⚠ WARNING: test-vm-a and test-vm-b-sameworker-as-a are on different nodes!"
fi

if [ "$VM_A_NODE_FINAL" != "$VM_B_DIFFERENTWORKER_AS_A_NODE" ]; then
    echo "✓ test-vm-a and test-vm-b-differentworker-as-a are on different nodes (for CUDN isolation testing)"
else
    echo "⚠ WARNING: test-vm-a and test-vm-b-differentworker-as-a are on the same node!"
fi
echo

echo "To SSH to VMs:"
echo "  virtctl -n cudn1 ssh -i $KEYFILE fedora@test-vm-a"
echo "  virtctl -n cudn1 ssh -i $KEYFILE fedora@test-vm-a-sameworker"
echo "  virtctl -n cudn1 ssh -i $KEYFILE fedora@test-vm-a-differentworker"
echo "  virtctl -n cudn2 ssh -i $KEYFILE fedora@test-vm-b"
echo "  virtctl -n cudn2 ssh -i $KEYFILE fedora@test-vm-b-sameworker-as-a"
echo "  virtctl -n cudn2 ssh -i $KEYFILE fedora@test-vm-b-differentworker-as-a"
echo
echo "VM Status:"
oc get vmi -A | grep test-vm
