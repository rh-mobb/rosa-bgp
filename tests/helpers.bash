#!/bin/bash
# Helper functions for BATS tests

# Setup jump pods for SSH access to VMs
# Call this from setup_file() in your bats test
setup_jump_pods() {
    echo "Creating jump pods for VM SSH access..." >&2

    # Create jump pod in cudn1
    cat <<EOF | oc apply -f - 2>&1 | grep -v "unchanged" || true
apiVersion: v1
kind: Pod
metadata:
  name: network-jump
  namespace: cudn1
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: network-jump
    image: registry.access.redhat.com/ubi9/toolbox:latest
    command: ["sleep", "infinity"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      runAsUser: 1000
EOF

    # Create jump pod in cudn2
    cat <<EOF | oc apply -f - 2>&1 | grep -v "unchanged" || true
apiVersion: v1
kind: Pod
metadata:
  name: network-jump-cudn2
  namespace: cudn2
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: network-jump-cudn2
    image: registry.access.redhat.com/ubi9/toolbox:latest
    command: ["sleep", "infinity"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      runAsUser: 1000
EOF

    # Wait for pods to be ready
    echo "Waiting for jump pods to be ready..." >&2
    oc wait --for=condition=Ready pod/network-jump -n cudn1 --timeout=60s >/dev/null 2>&1
    oc wait --for=condition=Ready pod/network-jump-cudn2 -n cudn2 --timeout=60s >/dev/null 2>&1

    echo "Jump pods ready" >&2
}

# Cleanup jump pods
# Call this from teardown_file() in your bats test
teardown_jump_pods() {
    echo "Cleaning up jump pods..." >&2
    oc delete pod network-jump -n cudn1 --ignore-not-found=true >/dev/null 2>&1
    oc delete pod network-jump-cudn2 -n cudn2 --ignore-not-found=true >/dev/null 2>&1
}

# Execute a command on a VM via SSH from a jump pod
# Usage: vm_exec <vm_name> <namespace> <command>
# Returns: exit code from the command executed on the VM
vm_exec() {
    local vm_name=$1
    local namespace=$2
    local command=$3
    local ssh_key="${SSH_KEY:-tests/test-vm-key}"
    local jump_pod="${JUMP_POD_PREFIX:-network-jump}"

    # Namespace-specific pod naming (cudn1 uses "network-jump", others use "network-jump-{namespace}")
    if [ "$namespace" != "cudn1" ]; then
        jump_pod="${jump_pod}-${namespace}"
    fi

    # Get VM IP
    local vm_ip=$(oc get vmi "$vm_name" -n "$namespace" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null)
    if [ -z "$vm_ip" ]; then
        echo "ERROR: Could not get IP for VM $vm_name in namespace $namespace" >&2
        return 1
    fi

    # Ensure SSH key is on jump pod (idempotent - only copies if not present)
    if ! oc exec -n "$namespace" "$jump_pod" -- test -f /tmp/test-vm-key 2>/dev/null; then
        oc cp "$ssh_key" "$namespace/$jump_pod:/tmp/test-vm-key" 2>&1 | grep -v "tar: Removing leading" || true
        oc exec -n "$namespace" "$jump_pod" -- chmod 600 /tmp/test-vm-key 2>/dev/null
    fi

    # Execute command via SSH
    oc exec -n "$namespace" "$jump_pod" -- \
        ssh -i /tmp/test-vm-key \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            -o LogLevel=ERROR \
            fedora@"$vm_ip" \
            "$command"
}

# Get VM IP address
# Usage: get_vm_ip <vm_name> <namespace>
get_vm_ip() {
    local vm_name=$1
    local namespace=$2
    oc get vmi "$vm_name" -n "$namespace" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null
}

# Wait for VM to be ready
# Usage: wait_for_vm <vm_name> <namespace> [timeout_seconds]
wait_for_vm() {
    local vm_name=$1
    local namespace=$2
    local timeout=${3:-300}  # Default 5 minutes

    echo "Waiting for VM $vm_name in namespace $namespace to be ready..." >&2
    oc wait --for=condition=Ready vmi/"$vm_name" -n "$namespace" --timeout="${timeout}s"
}

# Test SSH connectivity to a VM
# Usage: test_vm_ssh <vm_name> <namespace>
# Returns: 0 if SSH works, 1 otherwise
test_vm_ssh() {
    local vm_name=$1
    local namespace=$2

    vm_exec "$vm_name" "$namespace" "echo 'SSH OK'" >/dev/null 2>&1
}
