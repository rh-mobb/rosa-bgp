#!/usr/bin/env bats
# Test connectivity from CUDN VMs to endpoints on worker nodes

# Load helper functions
load ../../helpers

# Assert that VM can connect to worker node kubelet endpoint
assert_vm_can_connect_to_worker_endpoint() {
    local vm_name=$1
    local namespace=$2
    local worker_ip=$3

    # Try to curl the kubelet healthz endpoint - we expect connection success
    # but will get "Unauthorized" since we don't have credentials
    run vm_exec "$vm_name" "$namespace" "curl -s -m 5 -k https://$worker_ip:10250/healthz"
    # Exit code should be 0 (connection successful) and output should contain "Unauthorized"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Unauthorized" ]]
}

# Get worker node IP
setup() {
    # Get IP of a pod running on host network from subnet 1 (which will be a worker node IP)
    # We filter for IPs starting with 10.0.1. to ensure we get a node from the first subnet
    export WORKER_IP=$(oc get pods -n eni-srcdst-disable -o json | jq -r '.items[].status.podIP' 2>/dev/null | grep '^10\.0\.1\.' | head -1)
    if [ -z "$WORKER_IP" ]; then
        skip "Could not get worker node IP from subnet 1"
    fi
}

# Test: test-vm-a can connect to worker node kubelet
@test "test-vm-a (cudn1) can connect to worker node kubelet endpoint" {
    assert_vm_can_connect_to_worker_endpoint test-vm-a cudn1 "$WORKER_IP"
}

# Test: test-vm-b can connect to worker node kubelet
@test "test-vm-b (cudn2) can connect to worker node kubelet endpoint" {
    assert_vm_can_connect_to_worker_endpoint test-vm-b cudn2 "$WORKER_IP"
}
