#!/usr/bin/env bats
# Test connectivity from CUDN VMs to kube-dns

# Load helper functions
load ../../helpers

# Assert that VM can connect to DNS server on UDP/TCP
assert_vm_can_connect_to_dns() {
    local vm_name=$1
    local namespace=$2
    local dns_ip=$3
    local protocol=$4

    run vm_exec "$vm_name" "$namespace" "nc -vz${protocol} -w 2 $dns_ip 53"
    [ "$status" -eq 0 ]
}

# Assert that VM can resolve cluster DNS names via UDP
assert_vm_can_resolve_dns_udp() {
    local vm_name=$1
    local namespace=$2
    local dns_name=$3

    run vm_exec "$vm_name" "$namespace" "nslookup -novc $dns_name"
    [ "$status" -eq 0 ]
}

# Assert that VM can resolve cluster DNS names via TCP
assert_vm_can_resolve_dns_tcp() {
    local vm_name=$1
    local namespace=$2
    local dns_name=$3

    run vm_exec "$vm_name" "$namespace" "nslookup -vc $dns_name"
    [ "$status" -eq 0 ]
}

# Get kube-dns service IP
setup() {
    export DNS_IP=$(oc get svc -n openshift-dns dns-default -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if [ -z "$DNS_IP" ]; then
        skip "Could not get kube-dns service IP"
    fi
}

# Test: test-vm-a can connect to DNS on UDP
@test "test-vm-a (cudn1) can connect to kube-dns on UDP" {
    assert_vm_can_connect_to_dns test-vm-a cudn1 "$DNS_IP" "u"
}

# Test: test-vm-a can connect to DNS on TCP
@test "test-vm-a (cudn1) can connect to kube-dns on TCP" {
    assert_vm_can_connect_to_dns test-vm-a cudn1 "$DNS_IP" ""
}

# Test: test-vm-a can resolve via UDP
@test "test-vm-a (cudn1) can resolve kubernetes.default.svc.cluster.local via UDP" {
    assert_vm_can_resolve_dns_udp test-vm-a cudn1 "kubernetes.default.svc.cluster.local"
}

# Test: test-vm-a can resolve via TCP
@test "test-vm-a (cudn1) can resolve kubernetes.default.svc.cluster.local via TCP" {
    assert_vm_can_resolve_dns_tcp test-vm-a cudn1 "kubernetes.default.svc.cluster.local"
}

# Test: test-vm-b can connect to DNS on UDP
@test "test-vm-b (cudn2) can connect to kube-dns on UDP" {
    assert_vm_can_connect_to_dns test-vm-b cudn2 "$DNS_IP" "u"
}

# Test: test-vm-b can connect to DNS on TCP
@test "test-vm-b (cudn2) can connect to kube-dns on TCP" {
    assert_vm_can_connect_to_dns test-vm-b cudn2 "$DNS_IP" ""
}

# Test: test-vm-b can resolve via UDP
@test "test-vm-b (cudn2) can resolve kubernetes.default.svc.cluster.local via UDP" {
    assert_vm_can_resolve_dns_udp test-vm-b cudn2 "kubernetes.default.svc.cluster.local"
}

# Test: test-vm-b can resolve via TCP
@test "test-vm-b (cudn2) can resolve kubernetes.default.svc.cluster.local via TCP" {
    assert_vm_can_resolve_dns_tcp test-vm-b cudn2 "kubernetes.default.svc.cluster.local"
}
