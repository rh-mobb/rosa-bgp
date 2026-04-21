#!/bin/bash
# Helper functions for BATS tests
#
# Note: Jump pods (network-jump) are created by tests/setup/setup-vm-ssh.sh
# These helpers provide functions to interact with VMs via those jump pods

# Define test VMs - add more VMs here as needed
declare -A TEST_VMS=(
    [test-vm-a]=cudn1
    [test-vm-b]=cudn2
)

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

# ============================================================================
# Test Assertion Helpers
# These functions provide reusable test logic for common VM test scenarios
# ============================================================================

# Assert that cloud-init has completed on a VM
# Usage: assert_cloud_init_complete <vm_name> <namespace>
assert_cloud_init_complete() {
    local vm_name=$1
    local namespace=$2
    run vm_exec "$vm_name" "$namespace" "systemctl status cloud-final"
    [ "$status" -eq 0 ]
}

# Assert that HTTP service is responding on a VM
# Usage: assert_http_responding <vm_name> <namespace> <expected_pattern>
assert_http_responding() {
    local vm_name=$1
    local namespace=$2
    local expected_pattern=$3
    run vm_exec "$vm_name" "$namespace" "curl -s http://localhost"
    [ "$status" -eq 0 ]
    [[ "$output" =~ $expected_pattern ]]
}

# Assert that VM can ping an internet IP
# Usage: assert_can_ping_internet <vm_name> <namespace> <ip_address>
assert_can_ping_internet() {
    local vm_name=$1
    local namespace=$2
    local ip_address=${3:-8.8.8.8}
    run vm_exec "$vm_name" "$namespace" "ping -c 2 -W 2 $ip_address"
    [ "$status" -eq 0 ]
}

# Assert that VM can curl an internet domain
# Usage: assert_can_curl_internet <vm_name> <namespace> <url>
assert_can_curl_internet() {
    local vm_name=$1
    local namespace=$2
    local url=${3:-http://www.google.com}
    run vm_exec "$vm_name" "$namespace" "curl -s -I -m 5 $url"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "HTTP" ]]
}

# Assert that VM can do DNS lookups over UDP
# Usage: assert_can_dns_lookup_udp <vm_name> <namespace> <domain>
assert_can_dns_lookup_udp() {
    local vm_name=$1
    local namespace=$2
    local domain=${3:-google.com}
    run vm_exec "$vm_name" "$namespace" "nslookup -novc $domain"
    [ "$status" -eq 0 ]
}

# Assert that VM can do DNS lookups over TCP
# Usage: assert_can_dns_lookup_tcp <vm_name> <namespace> <domain>
assert_can_dns_lookup_tcp() {
    local vm_name=$1
    local namespace=$2
    local domain=${3:-google.com}
    run vm_exec "$vm_name" "$namespace" "nslookup -vc $domain"
    [ "$status" -eq 0 ]
}
