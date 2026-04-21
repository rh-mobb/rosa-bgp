#!/usr/bin/env bats
# Test connectivity for VMs on CUDN networks

load helpers

@test "test-vm-a has finished cloud-final" {
    run vm_exec test-vm-a cudn1 "systemctl status cloud-final"
    [ "$status" -eq 0 ]
}

@test "test-vm-b has finished cloud-final" {
    run vm_exec test-vm-b cudn2 "systemctl status cloud-final"
    [ "$status" -eq 0 ]
}

@test "test-vm-a has HTTP service responding" {
    run vm_exec test-vm-a cudn1 "curl -s http://localhost"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Test VM A" ]]
}

@test "test-vm-b has HTTP service responding" {
    run vm_exec test-vm-b cudn2 "curl -s http://localhost"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Test VM B" ]]
}
