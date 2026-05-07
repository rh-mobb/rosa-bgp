#!/usr/bin/env bats
# Test connectivity from CUDN VMs to EC2 instance in same VPC

# Load helper functions
load ../../helpers

# Assert that VM can ping EC2 instance
assert_vm_can_ping_ec2() {
    local vm_name=$1
    local namespace=$2
    local ec2_ip=$3

    run vm_exec "$vm_name" "$namespace" "ping -c 2 -W 2 $ec2_ip"
    [ "$status" -eq 0 ]
}

# Assert that VM can curl EC2 instance's HTTP server
assert_vm_can_curl_ec2() {
    local vm_name=$1
    local namespace=$2
    local ec2_ip=$3

    run vm_exec "$vm_name" "$namespace" "curl -s -I -m 5 http://$ec2_ip"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "HTTP" ]]
}

# Get test instance IP from terraform output
setup() {
    export TEST_INSTANCE_IP=$(terraform output -raw test_instance_private_ip 2>/dev/null)
    if [ -z "$TEST_INSTANCE_IP" ]; then
        skip "test_instance_private_ip not found in terraform output"
    fi
}

# Test: test-vm-a can ping EC2 instance
@test "test-vm-a (cudn1) can ping EC2 in same VPC" {
    assert_vm_can_ping_ec2 test-vm-a cudn1 "$TEST_INSTANCE_IP"
}

# Test: test-vm-a can curl EC2 instance
@test "test-vm-a (cudn1) can curl EC2 in same VPC" {
    assert_vm_can_curl_ec2 test-vm-a cudn1 "$TEST_INSTANCE_IP"
}

# Test: test-vm-b can ping EC2 instance
@test "test-vm-b (cudn2) can ping EC2 in same VPC" {
    assert_vm_can_ping_ec2 test-vm-b cudn2 "$TEST_INSTANCE_IP"
}

# Test: test-vm-b can curl EC2 instance
@test "test-vm-b (cudn2) can curl EC2 in same VPC" {
    assert_vm_can_curl_ec2 test-vm-b cudn2 "$TEST_INSTANCE_IP"
}
