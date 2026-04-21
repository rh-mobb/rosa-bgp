#!/usr/bin/env bats
# Test connectivity for VMs on CUDN networks

# Load helper functions
load ../../helpers

# Setup: Create jump pods once for the entire test file
setup_file() {
    setup_jump_pods
}

# Teardown: Clean up jump pods after all tests complete
teardown_file() {
    teardown_jump_pods
}

@test "test-vm-a can look up Internet domain names over UDP: google.com" {
    run vm_exec test-vm-a cudn1 "nslookup -novc google.com"
    [ "$status" -eq 0 ]
}

@test "test-vm-a can look up Internet domain names over TCP: google.com" {
    run vm_exec test-vm-a cudn1 "nslookup -vc google.com"
    [ "$status" -eq 0 ]
}

@test "test-vm-b can look up Internet domain names over UDP: google.com" {
    run vm_exec test-vm-b cudn2 "nslookup -novc google.com"
    [ "$status" -eq 0 ]
}

@test "test-vm-b can look up Internet domain names over TCP: google.com" {
    run vm_exec test-vm-b cudn2 "nslookup -vc google.com"
    [ "$status" -eq 0 ]
}
