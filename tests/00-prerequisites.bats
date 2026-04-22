#!/usr/bin/env bats
# Test connectivity for VMs on CUDN networks

load helpers

# Assert that cloud-init has completed on a VM
assert_cloud_init_complete() {
    local vm_name=$1
    local namespace=$2
    run vm_exec "$vm_name" "$namespace" "systemctl status cloud-final"
    [ "$status" -eq 0 ]
}

# Assert that HTTP service is responding on a VM
assert_http_responding() {
    local vm_name=$1
    local namespace=$2
    local expected_pattern=$3
    run vm_exec "$vm_name" "$namespace" "curl -s http://localhost"
    [ "$status" -eq 0 ]
    [[ "$output" =~ $expected_pattern ]]
}

@test "test-vm-a has finished cloud-final" {
    assert_cloud_init_complete test-vm-a cudn1
}

@test "test-vm-a-sameworker has finished cloud-final" {
    assert_cloud_init_complete test-vm-a-sameworker cudn1
}

@test "test-vm-b has finished cloud-final" {
    assert_cloud_init_complete test-vm-b cudn2
}

@test "test-vm-a has HTTP service responding" {
    assert_http_responding test-vm-a cudn1 "Test VM A"
}

@test "test-vm-a-sameworker has HTTP service responding" {
    assert_http_responding test-vm-a-sameworker cudn1 "Test VM A2"
}

@test "test-vm-b has HTTP service responding" {
    assert_http_responding test-vm-b cudn2 "Test VM B"
}
