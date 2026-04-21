#!/usr/bin/env bats
# Test connectivity for VMs on CUDN networks

load helpers

@test "test-vm-a has finished cloud-final" {
    assert_cloud_init_complete test-vm-a cudn1
}

@test "test-vm-b has finished cloud-final" {
    assert_cloud_init_complete test-vm-b cudn2
}

@test "test-vm-a has HTTP service responding" {
    assert_http_responding test-vm-a cudn1 "Test VM A"
}

@test "test-vm-b has HTTP service responding" {
    assert_http_responding test-vm-b cudn2 "Test VM B"
}
