#!/usr/bin/env bats
# Test connectivity from CUDN VM to NodePort services

# Load helper functions
load ../helpers

# Assert that VM can curl NodePort service
assert_vm_can_curl_nodeport() {
    local vm_name=$1
    local namespace=$2
    local node_ip=$3
    local nodeport=$4

    run vm_exec "$vm_name" "$namespace" "curl -s -m 5 http://$node_ip:$nodeport"
    [ "$status" -eq 0 ]
}

# Assert that VM cannot curl NodePort service (expected failure)
assert_vm_cannot_curl_nodeport() {
    local vm_name=$1
    local namespace=$2
    local node_ip=$3
    local nodeport=$4

    run vm_exec "$vm_name" "$namespace" "curl -s -m 5 http://$node_ip:$nodeport"
    [ "$status" -ne 0 ]
}

# Setup - gather all NodePort and node information
setup() {
    # Get node where test-vm-a is running
    export VM_A_NODE=$(oc get vmi test-vm-a -n cudn1 -o jsonpath='{.status.nodeName}' 2>/dev/null)
    if [ -z "$VM_A_NODE" ]; then
        skip "test-vm-a is not running. Run tests/setup/setup-vm-ssh.sh first."
    fi

    # Get node IP (internal IP) of test-vm-a's node
    export VM_A_NODE_IP=$(oc get node "$VM_A_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    if [ -z "$VM_A_NODE_IP" ]; then
        skip "Could not get IP for node $VM_A_NODE"
    fi

    # Test 1: NodePort(ETP=Cluster) with same node
    export NODEPORT_CLUSTER_SAMENODE=$(oc get svc hello-openshift-nodeport-samenode -n cudn1 -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ -n "$NODEPORT_CLUSTER_SAMENODE" ]; then
        local pod_node=$(oc get pod -n cudn1 -l app=hello-openshift-nodeport-samenode -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
        if [ "$pod_node" != "$VM_A_NODE" ]; then
            export SKIP_TEST1="Backing pod is not on the same node as test-vm-a (pod: $pod_node, vm: $VM_A_NODE)"
        fi
    fi

    # Test 2: NodePort(ETP=Cluster) with different node
    export NODEPORT_CLUSTER_DIFFNODE=$(oc get svc hello-openshift-nodeport-diffnode -n cudn1 -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ -n "$NODEPORT_CLUSTER_DIFFNODE" ]; then
        local pod_node=$(oc get pod -n cudn1 -l app=hello-openshift-nodeport-diffnode -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
        if [ "$pod_node" = "$VM_A_NODE" ]; then
            export SKIP_TEST2="Backing pod is on the same node as test-vm-a (pod: $pod_node, vm: $VM_A_NODE)"
        fi
    fi

    # Test 3: NodePort(ETP=Local) with same node
    export NODEPORT_LOCAL_SAMENODE=$(oc get svc hello-openshift-nodeport-local-samenode -n cudn1 -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ -n "$NODEPORT_LOCAL_SAMENODE" ]; then
        local pod_node=$(oc get pod -n cudn1 -l app=hello-openshift-nodeport-local-samenode -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
        if [ "$pod_node" != "$VM_A_NODE" ]; then
            export SKIP_TEST3="Backing pod is not on the same node as test-vm-a (pod: $pod_node, vm: $VM_A_NODE)"
        fi
    fi

    # Test 4: NodePort(ETP=Local) with 2 backend pods
    export NODEPORT_LOCAL_DIFFNODE=$(oc get svc hello-openshift-nodeport-local-diffnode -n cudn1 -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ -n "$NODEPORT_LOCAL_DIFFNODE" ]; then
        local pod_count=$(oc get pods -n cudn1 -l app=hello-openshift-nodeport-local-diffnode --field-selector=status.phase=Running -o json | jq '.items | length')
        if [ "$pod_count" != "2" ]; then
            export SKIP_TEST4="Expected 2 backend pods, found $pod_count"
        else
            local pod_nodes=$(oc get pods -n cudn1 -l app=hello-openshift-nodeport-local-diffnode -o jsonpath='{.items[*].spec.nodeName}')
            local same_node_count=$(echo "$pod_nodes" | tr ' ' '\n' | grep -c "^${VM_A_NODE}$" || true)
            local diff_node_count=$(echo "$pod_nodes" | tr ' ' '\n' | grep -cv "^${VM_A_NODE}$" || true)
            if [ "$same_node_count" != "1" ] || [ "$diff_node_count" != "1" ]; then
                export SKIP_TEST4="Expected 1 pod on same node as test-vm-a and 1 on different node (same: $same_node_count, diff: $diff_node_count)"
            fi
        fi
    fi

    # Test 5: NodePort(ETP=Local) with no local endpoint
    export NODEPORT_LOCAL_NOLOCAL=$(oc get svc hello-openshift-nodeport-local-nolocal -n cudn1 -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ -n "$NODEPORT_LOCAL_NOLOCAL" ]; then
        local pod_node=$(oc get pod -n cudn1 -l app=hello-openshift-nodeport-local-nolocal -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
        if [ -z "$pod_node" ]; then
            export SKIP_TEST5="Could not find backing pod"
        elif [ "$pod_node" = "$VM_A_NODE" ]; then
            export SKIP_TEST5="Backing pod is on the same node as test-vm-a (pod: $pod_node, vm: $VM_A_NODE) - expected different node"
        else
            # Get a different worker node (not VM_A_NODE and not pod_node)
            export DIFFERENT_NODE=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers -o custom-columns=NAME:.metadata.name | grep -v "$VM_A_NODE" | grep -v "$pod_node" | head -1)
            if [ -z "$DIFFERENT_NODE" ]; then
                export SKIP_TEST5="Could not find a third worker node (need one that's not test-vm-a's node and not the pod's node)"
            else
                export DIFFERENT_NODE_IP=$(oc get node "$DIFFERENT_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
                if [ -z "$DIFFERENT_NODE_IP" ]; then
                    export SKIP_TEST5="Could not get IP for node $DIFFERENT_NODE"
                fi
            fi
        fi
    fi
}

# Test 1: NodePort(ETP=Cluster) with same node
@test "test-vm-a can curl NodePort(externalTrafficPolicy=Cluster) service on same node" {
    [ -z "$NODEPORT_CLUSTER_SAMENODE" ] && skip "hello-openshift-nodeport-samenode service not found"
    [ -n "$SKIP_TEST1" ] && skip "$SKIP_TEST1"
    assert_vm_can_curl_nodeport test-vm-a cudn1 "$VM_A_NODE_IP" "$NODEPORT_CLUSTER_SAMENODE"
}

# Test 2: NodePort(ETP=Cluster) with different node
@test "test-vm-a can curl NodePort(externalTrafficPolicy=Cluster) service with pod on different node" {
    [ -z "$NODEPORT_CLUSTER_DIFFNODE" ] && skip "hello-openshift-nodeport-diffnode service not found"
    [ -n "$SKIP_TEST2" ] && skip "$SKIP_TEST2"
    assert_vm_can_curl_nodeport test-vm-a cudn1 "$VM_A_NODE_IP" "$NODEPORT_CLUSTER_DIFFNODE"
}

# Test 3: NodePort(ETP=Local) with same node
@test "test-vm-a can curl NodePort(externalTrafficPolicy=Local) service on same node" {
    [ -z "$NODEPORT_LOCAL_SAMENODE" ] && skip "hello-openshift-nodeport-local-samenode service not found"
    [ -n "$SKIP_TEST3" ] && skip "$SKIP_TEST3"
    assert_vm_can_curl_nodeport test-vm-a cudn1 "$VM_A_NODE_IP" "$NODEPORT_LOCAL_SAMENODE"
}

# Test 4: NodePort(ETP=Local) with 2 backend pods
@test "test-vm-a can curl NodePort(externalTrafficPolicy=Local) service with 2 backend pods (1 same node, 1 different)" {
    [ -z "$NODEPORT_LOCAL_DIFFNODE" ] && skip "hello-openshift-nodeport-local-diffnode service not found"
    [ -n "$SKIP_TEST4" ] && skip "$SKIP_TEST4"
    assert_vm_can_curl_nodeport test-vm-a cudn1 "$VM_A_NODE_IP" "$NODEPORT_LOCAL_DIFFNODE"
}

# Test 5: NodePort(ETP=Local) with no local endpoint (expected failure)
@test "test-vm-a cannot curl NodePort(externalTrafficPolicy=Local) service with no local endpoint (expected failure)" {
    [ -z "$NODEPORT_LOCAL_NOLOCAL" ] && skip "hello-openshift-nodeport-local-nolocal service not found"
    [ -n "$SKIP_TEST5" ] && skip "$SKIP_TEST5"
    assert_vm_cannot_curl_nodeport test-vm-a cudn1 "$DIFFERENT_NODE_IP" "$NODEPORT_LOCAL_NOLOCAL"
}
