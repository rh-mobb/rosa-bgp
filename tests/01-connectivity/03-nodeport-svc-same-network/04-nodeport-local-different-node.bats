#!/usr/bin/env bats
# Test connectivity from CUDN VM to NodePort service with externalTrafficPolicy=Local with 2 backend pods (one same node, one different)

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
    export NODEPORT=$(oc get svc hello-openshift-nodeport-local-diffnode -n cudn1 -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ -z "$NODEPORT" ]; then
        skip "hello-openshift-nodeport-local-diffnode service not found. Run tests/setup/setup-vm-ssh.sh first."
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

    # Verify there are 2 backend pods
    local pod_count=$(oc get pods -n cudn1 -l app=hello-openshift-nodeport-local-diffnode --field-selector=status.phase=Running -o json | jq '.items | length')
    if [ "$pod_count" != "2" ]; then
        skip "Expected 2 backend pods, found $pod_count"
    fi

    # Verify one pod is on same node as test-vm-a and one is on different node
    local pod_nodes=$(oc get pods -n cudn1 -l app=hello-openshift-nodeport-local-diffnode -o jsonpath='{.items[*].spec.nodeName}')
    local same_node_count=$(echo "$pod_nodes" | tr ' ' '\n' | grep -c "^${VM_A_NODE}$" || true)
    local diff_node_count=$(echo "$pod_nodes" | tr ' ' '\n' | grep -cv "^${VM_A_NODE}$" || true)

    if [ "$same_node_count" != "1" ] || [ "$diff_node_count" != "1" ]; then
        skip "Expected 1 pod on same node as test-vm-a and 1 on different node (same: $same_node_count, diff: $diff_node_count)"
    fi
}

# Test: test-vm-a can curl NodePort service with ETP=Local (2 backend pods, accessing via local node)
@test "test-vm-a can curl NodePort(externalTrafficPolicy=Local) service with 2 backend pods (1 same node, 1 different)" {
    assert_vm_can_curl_nodeport test-vm-a cudn1 "$NODE_IP" "$NODEPORT"
}
