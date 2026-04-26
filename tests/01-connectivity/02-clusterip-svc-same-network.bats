#!/usr/bin/env bats
# Test connectivity from CUDN VM to ClusterIP services

# Load helper functions
load ../helpers

# Assert that VM can curl ClusterIP service
assert_vm_can_curl_clusterip() {
    local vm_name=$1
    local namespace=$2
    local cluster_ip=$3

    run vm_exec "$vm_name" "$namespace" "curl -s -m 5 http://$cluster_ip:8080"
    [ "$status" -eq 0 ]
}

# Assert that VM cannot curl ClusterIP service (expected failure)
assert_vm_cannot_curl_clusterip() {
    local vm_name=$1
    local namespace=$2
    local cluster_ip=$3

    run vm_exec "$vm_name" "$namespace" "curl -s -m 5 http://$cluster_ip:8080"
    [ "$status" -ne 0 ]
}

# Setup - gather all ClusterIP and node information
setup() {
    # Get node where test-vm-a is running
    export VM_A_NODE=$(oc get vmi test-vm-a -n cudn1 -o jsonpath='{.status.nodeName}' 2>/dev/null)
    if [ -z "$VM_A_NODE" ]; then
        skip "test-vm-a is not running. Run tests/setup/setup-vm-ssh.sh first."
    fi

    # Test 1: ClusterIP(ITP=Cluster) with same node
    export CLUSTERIP_CLUSTER_SAMENODE=$(oc get svc hello-openshift-clusterip-samenode -n cudn1 -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if [ -n "$CLUSTERIP_CLUSTER_SAMENODE" ]; then
        local pod_node=$(oc get pod -n cudn1 -l app=hello-openshift-clusterip-samenode -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
        if [ "$pod_node" != "$VM_A_NODE" ]; then
            export SKIP_TEST1="Backing pod is not on the same node as test-vm-a (pod: $pod_node, vm: $VM_A_NODE)"
        fi
    fi

    # Test 2: ClusterIP(ITP=Cluster) with different node
    export CLUSTERIP_CLUSTER_DIFFNODE=$(oc get svc hello-openshift-clusterip-diffnode -n cudn1 -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if [ -n "$CLUSTERIP_CLUSTER_DIFFNODE" ]; then
        local pod_node=$(oc get pod -n cudn1 -l app=hello-openshift-clusterip-diffnode -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
        if [ "$pod_node" = "$VM_A_NODE" ]; then
            export SKIP_TEST2="Backing pod is on the same node as test-vm-a (pod: $pod_node, vm: $VM_A_NODE)"
        fi
    fi

    # Test 3: ClusterIP(ITP=Local) with same node
    export CLUSTERIP_LOCAL_SAMENODE=$(oc get svc hello-openshift-clusterip-local-samenode -n cudn1 -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if [ -n "$CLUSTERIP_LOCAL_SAMENODE" ]; then
        local pod_node=$(oc get pod -n cudn1 -l app=hello-openshift-clusterip-local-samenode -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
        if [ "$pod_node" != "$VM_A_NODE" ]; then
            export SKIP_TEST3="Backing pod is not on the same node as test-vm-a (pod: $pod_node, vm: $VM_A_NODE)"
        fi
    fi

    # Test 4: ClusterIP(ITP=Local) with different node
    export CLUSTERIP_LOCAL_DIFFNODE=$(oc get svc hello-openshift-clusterip-local-diffnode -n cudn1 -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if [ -n "$CLUSTERIP_LOCAL_DIFFNODE" ]; then
        local pod_node=$(oc get pod -n cudn1 -l app=hello-openshift-clusterip-local-diffnode -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
        if [ "$pod_node" = "$VM_A_NODE" ]; then
            export SKIP_TEST4="Backing pod is on the same node as test-vm-a (pod: $pod_node, vm: $VM_A_NODE)"
        fi
    fi
}

# Test 1: ClusterIP(ITP=Cluster) with same node - expected to succeed
@test "test-vm-a can curl ClusterIP(internalTrafficPolicy=Cluster) service on same node" {
    [ -z "$CLUSTERIP_CLUSTER_SAMENODE" ] && skip "hello-openshift-clusterip-samenode service not found"
    [ -n "$SKIP_TEST1" ] && skip "$SKIP_TEST1"
    assert_vm_can_curl_clusterip test-vm-a cudn1 "$CLUSTERIP_CLUSTER_SAMENODE"
}

# Test 2: ClusterIP(ITP=Cluster) with different node - expected to succeed
@test "test-vm-a can curl ClusterIP(internalTrafficPolicy=Cluster) service with pod on different node" {
    [ -z "$CLUSTERIP_CLUSTER_DIFFNODE" ] && skip "hello-openshift-clusterip-diffnode service not found"
    [ -n "$SKIP_TEST2" ] && skip "$SKIP_TEST2"
    assert_vm_can_curl_clusterip test-vm-a cudn1 "$CLUSTERIP_CLUSTER_DIFFNODE"
}

# Test 3: ClusterIP(ITP=Local) with same node - expected to succeed
@test "test-vm-a can curl ClusterIP(internalTrafficPolicy=Local) service on same node" {
    [ -z "$CLUSTERIP_LOCAL_SAMENODE" ] && skip "hello-openshift-clusterip-local-samenode service not found"
    [ -n "$SKIP_TEST3" ] && skip "$SKIP_TEST3"
    assert_vm_can_curl_clusterip test-vm-a cudn1 "$CLUSTERIP_LOCAL_SAMENODE"
}

# Test 4: ClusterIP(ITP=Local) with different node - expected NOT to succeed
@test "test-vm-a cannot curl ClusterIP(internalTrafficPolicy=Local) service with pod on different node (expected failure)" {
    [ -z "$CLUSTERIP_LOCAL_DIFFNODE" ] && skip "hello-openshift-clusterip-local-diffnode service not found"
    [ -n "$SKIP_TEST4" ] && skip "$SKIP_TEST4"
    assert_vm_cannot_curl_clusterip test-vm-a cudn1 "$CLUSTERIP_LOCAL_DIFFNODE"
}
