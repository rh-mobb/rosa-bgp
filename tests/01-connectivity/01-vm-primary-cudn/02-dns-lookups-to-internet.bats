#!/usr/bin/env bats
# Test connectivity for VMs on CUDN networks

# Load helper functions
load ../../helpers

# Assert that VM can do DNS lookups over UDP
assert_can_dns_lookup_udp() {
    local vm_name=$1
    local namespace=$2
    local domain=${3:-google.com}
    run vm_exec "$vm_name" "$namespace" "nslookup -novc $domain"
    [ "$status" -eq 0 ]
}

# Assert that VM can do DNS lookups over TCP
assert_can_dns_lookup_tcp() {
    local vm_name=$1
    local namespace=$2
    local domain=${3:-google.com}
    run vm_exec "$vm_name" "$namespace" "nslookup -vc $domain"
    [ "$status" -eq 0 ]
}

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
