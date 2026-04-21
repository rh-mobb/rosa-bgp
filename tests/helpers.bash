#!/bin/bash
# Helper functions for BATS tests - OPTIMIZED VERSION

# Setup jump pods for SSH access to VMs
# Call this from setup_file() in your bats test
setup_jump_pods() {
    # Check if pods already exist and are ready - skip recreation
    if oc get pod network-jump -n cudn1 &>/dev/null && \
       oc get pod network-jump-cudn2 -n cudn2 &>/dev/null; then
        if oc wait --for=condition=Ready pod/network-jump -n cudn1 --timeout=1s &>/dev/null && \
           oc wait --for=condition=Ready pod/network-jump-cudn2 -n cudn2 --timeout=1s &>/dev/null; then
            echo "Jump pods already exist and ready, skipping creation" >&2
            return 0
        fi
    fi

    echo "Creating jump pods for VM SSH access..." >&2

    # Create jump pod in cudn1 with SSH key secret mounted
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
    fsGroup: 1000
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
    volumeMounts:
    - name: ssh-key
      mountPath: /home/test-user/.ssh
      readOnly: true
  volumes:
  - name: ssh-key
    secret:
      secretName: test-vm-ssh-key
      defaultMode: 0400
EOF

    # Create jump pod in cudn2 with SSH key secret mounted
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
    fsGroup: 1000
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
    volumeMounts:
    - name: ssh-key
      mountPath: /home/test-user/.ssh
      readOnly: true
  volumes:
  - name: ssh-key
    secret:
      secretName: test-vm-ssh-key
      defaultMode: 0400
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
    # OPTIMIZATION: Skip deletion to avoid 64s wait per test file
    # Pods will be cleaned up at end of test suite or manually
    echo "Skipping jump pod cleanup (performance optimization)" >&2
    return 0
}

# Force cleanup jump pods (for final teardown)
# Only call this when you truly need to delete them
force_teardown_jump_pods() {
    echo "Force cleaning up jump pods..." >&2
    oc delete pod network-jump -n cudn1 --wait=false --ignore-not-found=true >/dev/null 2>&1
    oc delete pod network-jump-cudn2 -n cudn2 --wait=false --ignore-not-found=true >/dev/null 2>&1
}

# Execute a command on a VM via SSH from a jump pod
# Usage: vm_exec <vm_name> <namespace> <command>
# Returns: exit code from the command executed on the VM
vm_exec() {
    local vm_name=$1
    local namespace=$2
    local command=$3
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

    # Execute command via SSH using mounted secret
    oc exec -n "$namespace" "$jump_pod" -- \
        ssh -i /home/test-user/.ssh/id_ed25519 \
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
