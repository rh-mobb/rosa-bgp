* Connectivity - for each test case, verify the following work from source to destination: ping (except to k8s services), curl
    * VM with primary CUDN - Uses a VM in CUDN A, and a second VM in CUDN B
        * CUDN VM A/B traffic to Internet - expected to succeed - PASS
        * CUDN VM A/B DNS lookups to Internet UDP/TCP - expected to succeed - PASS
        * EC2 instance in same VPC to CUDN A/B VM - expected to succeed - PASS
            * Note: A flapping problem was observed in bidirectional communication between a VM and an EC2 instance on 4.20.17, but is fixed by 4.21.8. This was originally believed to be because of live migration, but that was a red herring. Traffic was egressing from the CUDN through nodes that were not `bgp_router` nodes, and seemed to be stopping at the ENI, likely because of some combination of src/dest checks and security groups. The expected behavior is that traffic egresses from the same node the VM is on.
            * Not yet tested: Packet loss after 15 min of pings to confirm the flapping problem is not happening.
        * EC2 instance in external VPC to transit gateway to CUDN VM A/B - expected to succeed - PASS
        * CUDN VM A/B to EC2 instance in same VPC - expected to succeed - PASS
        * CUDN VM A/B to transit gateway to EC2 instance in external VPC - expected to succeed - PASS
        * CUDN VM A/B to kapi - expected to succeed - PASS
            * Kubernetes service ClusterIP tested: `172.30.0.1`
            * TCP/HTTPS connectivity to kapi succeeded
            * `/version` and `/readyz` returned 200
            * `GET /` returned 403 as `system:anonymous`, which is expected for unauthenticated access
        * CUDN VM A/B to kube dns UDP/TCP - expected to succeed - PASS
            * VM DNS server is `172.30.0.10`
            * reachability to DNS server via nc over UDP and TCP - PASS
            * name resolution: `kubernetes.default.svc.cluster.local` over UDP/TCP - PASS
        * CUDN VM A/B to port on worker node host API service - expected to succeed - PASS
            * Curl to kubelet healthz endpoint on worker:10250/healthz - PASS
            * Note: See [tests/qe-pod-worker-node-service.txt](tests/qe-pod-worker-node-service.txt) for what QE tried previously
        * CUDN A VM to CUDN A VM (on the same node) - expected to succeed - PASS
        * CUDN A VM to CUDN A VM (on a different node) - expected to succeed - PASS
        * CUDN A VM to CUDN A VM (different node) - expected to succeed - PASS
        * CUDN A VM to CUDN B VM (on the same node) - expected to not succeed - PASS
            * This was with advertised-udn-isolation-mode set to strict, the default. It's possible there would be a different result if it were set to loose.
        * CUDN A VM to CUDN B VM (on a different node) - expected to not succeed - PASS
        * Worker node (via `oc debug node`) same host to CUDN A/B VM - expected to not succeed - PASS
            * UDNs are expected to isolate networking even on the same host
        * Worker node (via `oc debug node`) diff host to CUDN A/B VM - expected to not succeed - PASS
        * CUDN A VM traffic in and out to VPC continue to work after VM is live-migrated - expected to succeed - PASS
    * ClusterIP Service with same L2 network
        * CUDN VM to clusterIP(internalTrafficPolicy=Cluster) with same node - expected to succeed - PASS
        * CUDN VM to clusterIP(internalTrafficPolicy=Cluster) with diff node - expected to succeed - PASS
        * CUDN VM to clusterIP(internalTrafficPolicy=Local) with same node - expected to succeed - PASS
        * CUDN VM to clusterIP(internalTrafficPolicy=Local) with diff node - expected to not succeed - PASS
    * NodePort Service with same L2 network
        * CUDN VM to NodePort(ETP=Cluster) with same node - expected to succeed - PASS
        * CUDN VM to NodePort(ETP=Cluster) with diff node - expected to succeed - PASS
        * CUDN VM to NodePort(ETP=Local) with same node - expected to succeed - PASS
        * CUDN VM to NodePort(ETP=Local) with diff node (destination with two backend pods/VMs, one is same as source VM, one is different) - expected to succeed - PASS
        * CUDN VM to NodePort(ETP=Local) with diff node (the source VM is different from any destinaton endpoints nodes) - expected to not succeed - PASS
            * Note: must have ITP=Cluster AND ETP=Local for traffic to not be passed. When ITP not set, traffic is passed.
    * NodePort service with different L2 network
        * CUDN VM to NodePort(ETP=Cluster) with same node - expected not to succeed - PASS TODO
        * CUDN VM to NodePort(ETP=Cluster) with diff node - expected to succeed - PASS TODO
        * CUDN VM to NodePort(ETP=Local) with same node - expected not to succeed - PASS
        * CUDN VM to NodePort(ETP=Local) with diff node (the source VM is different from any destinaton endpoints nodes) - expected not to succeed
    * NodePort service on default pod network
        * CUDN VM to NodePort(ETP=Cluster) with same node - expected not to succeed - PASS
        * CUDN VM to NodePort(ETP=Cluster) with diff node - expected not to succeed - PASS
        * CUDN VM to NodePort(ETP=Local) with same node - expected not to succeed - PASS
        * CUDN VM to NodePort(ETP=Local) with diff node (destination with two backend pods, one is same as source VM, one is different) - expected to not succeed - PASS
        * CUDN VM to NodePort(ETP=Local) with diff node (the source VM is different from any destinaton endpoints nodes) - expected to not succeed - PASS
            * Note: Tested with ITP=Cluster AND ETP=Local
* Connectivity through node lifecycle events
    * Failure of worker node that is the route next hop (simulate by forcing termination through EC2 console). Traffic should continue being passed.
        * CUDN VM to EC2 instance in same VPC - expected to succeed - PASS
            * No packet loss was observed when ping ran with default 1 second interval
        * CUDN VM to same VPC to transit gateway to EC2 instance in different VPC - expected to succeed - PASS
            * No packet loss was observed when ping ran with default 1 second interval
        * EC2 instance in same VPC to CUDN VM - expected to succeed - PASS
            * No packet loss was observed when ping ran with default 1 second interval
        * EC2 instance in different VPC to transit gateway to same VPC to CUDN VM - expected to succeed - PASS
            * No packet loss was observed when ping ran with default 1 second interval
    * MachinePool scaledown causes worker node that is the route next hop to be deleted
        * CUDN VM to EC2 instance in same VPC - expected to succeed
        * CUDN VM to same VPC to transit gateway to EC2 instance in different VPC - expected to succeed
        * EC2 instance in same VPC to CUDN VM - expected to succeed
        * EC2 instance in different VPC to transit gateway to same VPC to CUDN VM - expected to succeed
    * Version upgrade applied to MachinePool containing worker node that is the next route hop (causing worker node replacement and IP change)
        * CUDN VM to EC2 instance in same VPC - expected to succeed
        * CUDN VM to same VPC to transit gateway to EC2 instance in different VPC - expected to succeed
        * EC2 instance in same VPC to CUDN VM - expected to succeed
        * EC2 instance in different VPC to transit gateway to same VPC to CUDN VM - expected to succeed
* eni-srcdst-disable DaemonSet should configure new nodes to be traffic next hop
    * Connectivity from EC2 to CUDN VM and CUDN VM to EC2 after DaemonSet is instantiated on cluster that has not had `disable_src_dst_check.sh` run - expected to succeed - PASS
    * Connectivity from EC2 to CUDN VM and CUDN VM to EC2 should be maintained during all of the following scenarios
        * MachinePool scale up - expected to succeed - PASS
        * Cluster upgrade - expected to succeed - PARTIAL
            * Routes and peers were configured correctly. However, this depends upon live migration working correctly to fully pass.
* Route server peers during node lifecycle events
    * Route Server gets peers for new nodes - expected to succeed - PASS
    * Route server has old peers cleaned up when nodes go away - expected to succeed - PASS
