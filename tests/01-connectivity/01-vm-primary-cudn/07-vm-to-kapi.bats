#!/usr/bin/env bats
# Test connectivity from CUDN VMs to Kubernetes API server

# Load helper functions
load ../../helpers

# Assert that VM can access kapi endpoint with expected status
assert_vm_can_access_kapi() {
    local vm_name=$1
    local namespace=$2
    local kapi_ip=$3
    local endpoint=$4
    local expected_status=$5

    run vm_exec "$vm_name" "$namespace" "curl -k -s -o /dev/null -w '%{http_code}' https://$kapi_ip:443$endpoint"
    [ "$status" -eq 0 ]
    [[ "$output" == "$expected_status" ]]
}

# Get Kubernetes API service IP
setup() {
    export KAPI_IP=$(oc get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if [ -z "$KAPI_IP" ]; then
        skip "Could not get Kubernetes API service IP"
    fi
}

# Test: test-vm-a can access /version (200)
@test "test-vm-a (cudn1) can access kapi /version endpoint" {
    assert_vm_can_access_kapi test-vm-a cudn1 "$KAPI_IP" "/version" "200"
}

# Test: test-vm-a can access /readyz (200)
@test "test-vm-a (cudn1) can access kapi /readyz endpoint" {
    assert_vm_can_access_kapi test-vm-a cudn1 "$KAPI_IP" "/readyz" "200"
}

# Test: test-vm-a gets 403 on / (unauthenticated)
@test "test-vm-a (cudn1) gets 403 on kapi / endpoint" {
    assert_vm_can_access_kapi test-vm-a cudn1 "$KAPI_IP" "/" "403"
}

# Test: test-vm-b can access /version (200)
@test "test-vm-b (cudn2) can access kapi /version endpoint" {
    assert_vm_can_access_kapi test-vm-b cudn2 "$KAPI_IP" "/version" "200"
}

# Test: test-vm-b can access /readyz (200)
@test "test-vm-b (cudn2) can access kapi /readyz endpoint" {
    assert_vm_can_access_kapi test-vm-b cudn2 "$KAPI_IP" "/readyz" "200"
}

# Test: test-vm-b gets 403 on / (unauthenticated)
@test "test-vm-b (cudn2) gets 403 on kapi / endpoint" {
    assert_vm_can_access_kapi test-vm-b cudn2 "$KAPI_IP" "/" "403"
}
