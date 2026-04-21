#!/usr/bin/env bats
# Test connectivity for VMs on CUDN networks

# Load helper functions
load ../../helpers

@test "test-vm-a can look up Internet domain names over UDP: google.com" {
    assert_can_dns_lookup_udp test-vm-a cudn1 google.com
}

@test "test-vm-a can look up Internet domain names over TCP: google.com" {
    assert_can_dns_lookup_tcp test-vm-a cudn1 google.com
}

@test "test-vm-b can look up Internet domain names over UDP: google.com" {
    assert_can_dns_lookup_udp test-vm-b cudn2 google.com
}

@test "test-vm-b can look up Internet domain names over TCP: google.com" {
    assert_can_dns_lookup_tcp test-vm-b cudn2 google.com
}
