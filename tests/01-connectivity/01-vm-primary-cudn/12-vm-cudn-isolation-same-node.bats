#!/usr/bin/env bats
# Test CUDN isolation between VMs on different CUDNs on the same node

# Load helper functions
load ../../helpers

# Assert that ping fails between isolated CUDNs
assert_vm_cannot_ping_vm() {
    local source_vm=$1
    local source_ns=$2
    local target_ip=$3

    run vm_exec "$source_vm" "$source_ns" "ping -c 2 -W 2 $target_ip"
    # Ping should fail (non-zero exit code)
    [ "$status" -ne 0 ]
}

# Assert that curl fails between isolated CUDNs
assert_vm_cannot_curl_vm() {
    local source_vm=$1
    local source_ns=$2
    local target_ip=$3

    run vm_exec "$source_vm" "$source_ns" "curl -s -m 3 http://$target_ip"
    # Curl should fail (non-zero exit code)
    [ "$status" -ne 0 ]
}

# Setup and verify isolation mode and node placement
setup() {
    # Check that advertised-udn-isolation-mode is strict (or not set, which defaults to strict)
    local isolation_mode=$(oc get clusteruserdefinednetwork cluster-udn-prod -o jsonpath='{.spec.network.layer2.advertisedUDNIsolationMode}' 2>/dev/null)

    # If not set, it defaults to "Strict"
    if [ -z "$isolation_mode" ]; then
        export ISOLATION_MODE="Strict (default)"
    else
        export ISOLATION_MODE="$isolation_mode"
        if [ "$isolation_mode" != "Strict" ]; then
            skip "advertised-udn-isolation-mode is not Strict: $isolation_mode"
        fi
    fi

    export VM_B_SAMEWORKER_AS_A_IP=$(get_vm_ip test-vm-b-sameworker-as-a cudn2 2>/dev/null)
    if [ -z "$VM_B_SAMEWORKER_AS_A_IP" ]; then
        skip "test-vm-b-sameworker-as-a is not running. Run tests/setup/setup-vm-ssh.sh first."
    fi

    # Verify VMs are on the same node
    local vm_a_node=$(oc get vmi test-vm-a -n cudn1 -o jsonpath='{.status.nodeName}' 2>/dev/null)
    local vm_b_sameworker_as_a_node=$(oc get vmi test-vm-b-sameworker-as-a -n cudn2 -o jsonpath='{.status.nodeName}' 2>/dev/null)

    if [ "$vm_a_node" != "$vm_b_sameworker_as_a_node" ]; then
        skip "test-vm-a and test-vm-b-sameworker-as-a are on different nodes"
    fi
}

# Test: Verify advertised-udn-isolation-mode is Strict
@test "advertised-udn-isolation-mode is Strict (default)" {
    [[ "$ISOLATION_MODE" =~ "Strict" ]]
}

# Test: test-vm-a cannot ping test-vm-b-sameworker-as-a (different CUDN, same node)
@test "test-vm-a cannot ping test-vm-b-sameworker-as-a (CUDN isolation, same node)" {
    assert_vm_cannot_ping_vm test-vm-a cudn1 "$VM_B_SAMEWORKER_AS_A_IP"
}

# Test: test-vm-a cannot curl test-vm-b-sameworker-as-a (different CUDN, same node)
@test "test-vm-a cannot curl test-vm-b-sameworker-as-a (CUDN isolation, same node)" {
    assert_vm_cannot_curl_vm test-vm-a cudn1 "$VM_B_SAMEWORKER_AS_A_IP"
}
