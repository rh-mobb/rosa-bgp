#!/usr/bin/env bats
# Test connectivity for VMs on CUDN networks

# Load helper functions
load ../../helpers

# Test: VM A can reach the internet
@test "test-vm-a can ping Internet: 8.8.8.8" {
    assert_can_ping_internet test-vm-a cudn1 8.8.8.8
}

@test "test-vm-a can curl Internet: google.com" {
    assert_can_curl_internet test-vm-a cudn1 http://www.google.com
}

# Test: VM B can reach the internet
@test "test-vm-b can ping Internet: 8.8.8.8" {
    assert_can_ping_internet test-vm-b cudn2 8.8.8.8
}

@test "test-vm-b can curl Internet: google.com" {
    assert_can_curl_internet test-vm-b cudn2 http://www.google.com
}
