#!/usr/bin/env bats
# Test connectivity from CUDN VM to NodePort service with externalTrafficPolicy=Local on same node

# Load helper functions
load ../../helpers

# Assert that VM can curl NodePort service
assert_vm_can_curl_nodeport() {
    local vm_name=$1
    local namespace=$2
    local node_ip=$3
    local nodeport=$4

    run vm_exec "$vm_name" "$namespace" "curl -s -m 5 http://$node_ip:$nodeport"
    [ "$status" -eq 0 ]
}

# Get NodePort and node IP
setup() {
    # Get NodePort number
    export NODEPORT=$(oc get svc hello-openshift-nodeport-local-samenode -n cudn1 -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ -z "$NODEPORT" ]; then
        skip "hello-openshift-nodeport-local-samenode service not found. Run tests/setup/setup-vm-ssh.sh first."
    fi

    # Get node where test-vm-a is running
    export VM_A_NODE=$(oc get vmi test-vm-a -n cudn1 -o jsonpath='{.status.nodeName}' 2>/dev/null)
    if [ -z "$VM_A_NODE" ]; then
        skip "test-vm-a is not running. Run tests/setup/setup-vm-ssh.sh first."
    fi

    # Get node IP (internal IP)
    export NODE_IP=$(oc get node "$VM_A_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    if [ -z "$NODE_IP" ]; then
        skip "Could not get IP for node $VM_A_NODE"
    fi

    # Verify backing pod is on the same node as test-vm-a
    local pod_node_name=$(oc get pod -n cudn1 -l app=hello-openshift-nodeport-local-samenode -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)

    if [ "$pod_node_name" != "$VM_A_NODE" ]; then
        skip "Backing pod is not on the same node as test-vm-a (pod: $pod_node_name, vm: $VM_A_NODE)"
    fi
}

# Test: test-vm-a can curl NodePort service with ETP=Local on same node
@test "test-vm-a can curl NodePort(externalTrafficPolicy=Local) service on same node" {
    assert_vm_can_curl_nodeport test-vm-a cudn1 "$NODE_IP" "$NODEPORT"
}
