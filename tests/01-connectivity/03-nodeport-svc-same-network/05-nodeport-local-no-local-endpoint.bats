#!/usr/bin/env bats
# Test connectivity from CUDN VM to NodePort service with externalTrafficPolicy=Local with no local endpoint (expected to fail)

# Load helper functions
load ../../helpers

# Assert that VM cannot curl NodePort service (expected failure)
assert_vm_cannot_curl_nodeport() {
    local vm_name=$1
    local namespace=$2
    local node_ip=$3
    local nodeport=$4

    run vm_exec "$vm_name" "$namespace" "curl -s -m 5 http://$node_ip:$nodeport"
    [ "$status" -ne 0 ]
}

# Get NodePort and node IP
setup() {
    # Get NodePort number
    export NODEPORT=$(oc get svc hello-openshift-nodeport-local-nolocal -n cudn1 -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ -z "$NODEPORT" ]; then
        skip "hello-openshift-nodeport-local-nolocal service not found. Run tests/setup/setup-vm-ssh.sh first."
    fi

    # Get node where test-vm-a is running
    export VM_A_NODE=$(oc get vmi test-vm-a -n cudn1 -o jsonpath='{.status.nodeName}' 2>/dev/null)
    if [ -z "$VM_A_NODE" ]; then
        skip "test-vm-a is not running. Run tests/setup/setup-vm-ssh.sh first."
    fi

    # Get node where backing pod is running
    local pod_node_name=$(oc get pod -n cudn1 -l app=hello-openshift-nodeport-local-nolocal -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
    if [ -z "$pod_node_name" ]; then
        skip "Could not find backing pod"
    fi

    # Verify backing pod is NOT on the same node as test-vm-a
    if [ "$pod_node_name" = "$VM_A_NODE" ]; then
        skip "Backing pod is on the same node as test-vm-a (pod: $pod_node_name, vm: $VM_A_NODE) - expected different node"
    fi

    # Get a different worker node (not VM_A_NODE and not pod_node_name)
    export DIFFERENT_NODE=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers -o custom-columns=NAME:.metadata.name | grep -v "$VM_A_NODE" | grep -v "$pod_node_name" | head -1)
    if [ -z "$DIFFERENT_NODE" ]; then
        skip "Could not find a third worker node (need one that's not test-vm-a's node and not the pod's node)"
    fi

    # Get IP of the different node
    export NODE_IP=$(oc get node "$DIFFERENT_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    if [ -z "$NODE_IP" ]; then
        skip "Could not get IP for node $DIFFERENT_NODE"
    fi
}

# Test: test-vm-a cannot curl NodePort service with ETP=Local when no local endpoint exists (expected failure)
@test "test-vm-a cannot curl NodePort(externalTrafficPolicy=Local) service with no local endpoint (expected failure)" {
    assert_vm_cannot_curl_nodeport test-vm-a cudn1 "$NODE_IP" "$NODEPORT"
}
