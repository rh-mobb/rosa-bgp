#!/usr/bin/env bats
# Test connectivity between VMs on same CUDN network but different nodes

# Load helper functions
load ../../helpers

# Assert that VM can ping another VM
assert_vm_can_ping_vm() {
    local source_vm=$1
    local source_ns=$2
    local target_ip=$3

    run vm_exec "$source_vm" "$source_ns" "ping -c 2 -W 2 $target_ip"
    [ "$status" -eq 0 ]
}

# Assert that VM can curl another VM's HTTP server
assert_vm_can_curl_vm() {
    local source_vm=$1
    local source_ns=$2
    local target_ip=$3

    run vm_exec "$source_vm" "$source_ns" "curl -s -I -m 5 http://$target_ip"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "HTTP" ]]
}

# Get test-vm-a-differentworker IP
setup() {
    export VM_A_DIFFERENTWORKER_IP=$(get_vm_ip test-vm-a-differentworker cudn1 2>/dev/null)
    if [ -z "$VM_A_DIFFERENTWORKER_IP" ]; then
        skip "test-vm-a-differentworker is not running. Run tests/setup/setup-vm-ssh.sh first."
    fi

    # Verify VMs are on different nodes
    local vm_a_node=$(oc get vmi test-vm-a -n cudn1 -o jsonpath='{.status.nodeName}' 2>/dev/null)
    local vm_a_diff_node=$(oc get vmi test-vm-a-differentworker -n cudn1 -o jsonpath='{.status.nodeName}' 2>/dev/null)

    if [ "$vm_a_node" = "$vm_a_diff_node" ]; then
        skip "test-vm-a and test-vm-a-differentworker are on the same node"
    fi
}

# Test: test-vm-a can ping test-vm-a-differentworker
@test "test-vm-a can ping test-vm-a-differentworker (different node, same CUDN)" {
    assert_vm_can_ping_vm test-vm-a cudn1 "$VM_A_DIFFERENTWORKER_IP"
}

# Test: test-vm-a can curl test-vm-a-differentworker
@test "test-vm-a can curl test-vm-a-differentworker (different node, same CUDN)" {
    assert_vm_can_curl_vm test-vm-a cudn1 "$VM_A_DIFFERENTWORKER_IP"
}
