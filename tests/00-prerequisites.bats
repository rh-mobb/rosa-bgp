#!/usr/bin/env bats
# Test connectivity for VMs on CUDN networks

load helpers

setup_file() {
    setup_jump_pods
}

teardown_file() {
    teardown_jump_pods
}

@test "test-vm-a has HTTP service responding" {
    vm_ip=$(get_vm_ip test-vm-a cudn1)
    run vm_exec test-vm-a cudn1 "curl -s http://localhost"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Test VM A" ]]
}

@test "test-vm-b has HTTP service responding" {
    vm_ip=$(get_vm_ip test-vm-b cudn2)
    run vm_exec test-vm-b cudn2 "curl -s http://localhost"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Test VM B" ]]
}
