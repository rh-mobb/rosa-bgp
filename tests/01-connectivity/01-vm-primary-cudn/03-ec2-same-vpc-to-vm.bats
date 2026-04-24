#!/usr/bin/env bats
# Test connectivity from EC2 instance in same VPC to CUDN VMs

# Load helper functions
load ../../helpers

# Assert that EC2 instance can ping a VM
assert_ec2_can_ping_vm() {
    local vm_name=$1
    local namespace=$2
    local instance_id=$3

    # Get VM IP
    local vm_ip=$(get_vm_ip "$vm_name" "$namespace")
    [ -n "$vm_ip" ] || {
        echo "Failed to get IP for VM $vm_name in namespace $namespace"
        return 1
    }

    run ec2_exec "$instance_id" "ping -c 2 -W 2 $vm_ip"
    [ "$status" -eq 0 ]
}

# Assert that EC2 instance can curl a VM's HTTP server
assert_ec2_can_curl_vm() {
    local vm_name=$1
    local namespace=$2
    local instance_id=$3

    # Get VM IP
    local vm_ip=$(get_vm_ip "$vm_name" "$namespace")
    [ -n "$vm_ip" ] || {
        echo "Failed to get IP for VM $vm_name in namespace $namespace"
        return 1
    }

    run ec2_exec "$instance_id" "curl -s -I -m 5 http://$vm_ip"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "HTTP" ]]
}

# Get test instance ID from terraform output
setup() {
    export TEST_INSTANCE_ID=$(terraform output -raw test_instance_id 2>/dev/null)
    if [ -z "$TEST_INSTANCE_ID" ]; then
        skip "test_instance_id not found in terraform output"
    fi
}

# Test: EC2 instance can ping test-vm-a
@test "EC2 instance can ping test-vm-a (cudn1)" {
    assert_ec2_can_ping_vm test-vm-a cudn1 "$TEST_INSTANCE_ID"
}

# Test: EC2 instance can curl test-vm-a
@test "EC2 instance can curl test-vm-a (cudn1)" {
    assert_ec2_can_curl_vm test-vm-a cudn1 "$TEST_INSTANCE_ID"
}

# Test: EC2 instance can ping test-vm-b
@test "EC2 instance can ping test-vm-b (cudn2)" {
    assert_ec2_can_ping_vm test-vm-b cudn2 "$TEST_INSTANCE_ID"
}

# Test: EC2 instance can curl test-vm-b
@test "EC2 instance can curl test-vm-b (cudn2)" {
    assert_ec2_can_curl_vm test-vm-b cudn2 "$TEST_INSTANCE_ID"
}
