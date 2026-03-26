* Connectivity - for each test case, verify the following work from source to destination: ping, curl
    * VM with primary CUDN - Uses a VM in CUDN A, and a second VM in CUDN B
        * CUDN VM A/B traffic to Internet - expected to succeed - PASS
        * EC2 instance in same VPC to CUDN A/B VM - expected to succeed - PASS
        * EC2 instance in external VPC to transit gateway to CUDN VM A/B - expected to succeed - PASS
        * CUDN VM A/B to EC2 instance in same VPC - expected to succeed - PASS
        * CUDN VM A/B to transit gateway to EC2 instance in external VPC - expected to succeed - PASS
        * CUDN VM A/B to kapi - expected to succeed - PASS
            * ping to public and service IP failed
            * TCP/HTTPS to kapi succeeded
            * /version and /readyz returned 200
            * GET / returned 403 as system:anonymous, which is expected for unauthenticated access
        * CUDN VM A/B to kube dns - expected to succeed - PARTIAL
            * VM DNS server is 172.30.0.10
            * public API hostname resolved successfully - PASS
            * TCP/53 connectivity to 172.30.0.10 succeeded - PASS
            * kubernetes.default.svc.cluster.local did not resolve - FAIL
        * CUDN VM A/B to port on worker node host API service - needs clarification
        * CUDN A VM to CUDN A VM (on the same node) - expected to succeed
        * CUDN A VM to CUDN A VM (on a different node) - expected to succeed - PASS
        * CUDN A VM to CUDN A VM (different node) - expected to succeed - PASS
            * vm0: 10.100.0.10 on ip-10-0-1-238.ca-central-1.compute.internal
            * vm1: 10.100.0.11 on ip-10-0-2-18.ca-central-1.compute.internal
            * ping: PASS
            * nc 8081: PASS
            * curl http://10.100.0.11:8081: PASS (HTTP 200 OK)
        * CUDN A VM to CUDN B VM (on the same node) - expected to not succeed - PASS
        * CUDN A VM to CUDN B VM (on a different node) - expected to not succeed - PASS- expected to succeed
        * Worker node (via `oc debug node`) same host to CUDN A/B VM - expected to not succeed - PASS
            * UDNs are expected to isolate networking even on the same host
        * Worker node (via `oc debug node`) diff host to CUDN A/B VM - expected to not succeed - PASS
    * ClusterIP Service with same L2 network
        * CUDN VM to clusterIP(internalTrafficPolicy=Cluster) with same node - expected to succeed - PASS
        * CUDN VM to clusterIP(internalTrafficPolicy=Cluster) with diff node - expected to succeed - PASS
        * CUDN VM to clusterIP(internalTrafficPolicy=Local) with same node - expected to succeed - FAIL
            * Possibly covered by https://redhat.atlassian.net/browse/OCPBUGS-59693
        * CUDN VM to clusterIP(internalTrafficPolicy=Local) with diff node - expected to not succeed - PASS
        * Expose CUDN VM through ClusterIP service, access by CUDN VM on same node - expected to succeed
        * Expose CUDN VM through ClusterIP service, access by CUDN VM on diff node - expected to succeed
    * NodePort Service with same L2 network
        * CUDN VM to NodePort(ETP=Cluster) with same node - expected to succeed
        * CUDN VM to NodePort(ETP=Cluster) with diff node - expected to succeed
        * CUDN VM to NodePort(ETP=Local) with same node - expected to succeed
        * CUDN VM to NodePort(ETP=Local) with diff node (destionation with two backend pods/VMs, one is same as source VM, one is different) - expected to succeed
        * CUDN VM to NodePort(ETP=Local) with diff node (the source VM is different from any destinaton endpoints nodes) - expected to not succeed
        * Expose CUDN VM through NodePort service, access by CUDN VM on same node - expected to succeed
        * Expose CUDN VM through NodePort service, access by CUDN VM on diff node - expected to succeed
    * NodePort service with different L2 network
        * CUDN VM to NodePort(ETP=Cluster) with same node - expected not to succeed
        * CUDN VM to NodePort(ETP=Cluster) with diff node - expected to succeed
        * CUDN VM to NodePort(ETP=Local) with same node - expected not to succeed
        * CUDN VM to NodePort(ETP=Local) with diff node (destination with two backend VMs, one is same as source VM, one is different) - expected to succeed
        * CUDN VM to NodePort(ETP=Local) with diff node (the source VM is different from any destinaton endpoints nodes) - expected not to succeed
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
        * CUDN VM to EC2 instance in same VPC - expected to succeed - PASS
        * CUDN VM to same VPC to transit gateway to EC2 instance in different VPC - expected to succeed - PASS
        * EC2 instance in same VPC to CUDN VM - expected to succeed - PASS
        * EC2 instance in different VPC to transit gateway to same VPC to CUDN VM - expected to succeed - PASS
    * Version upgrade applied to MachinePool containing worker node that is the next route hop (causing worker node replacement and IP change)
        * CUDN VM to EC2 instance in same VPC - expected to succeed
        * CUDN VM to same VPC to transit gateway to EC2 instance in different VPC - expected to succeed
        * EC2 instance in same VPC to CUDN VM - expected to succeed
        * EC2 instance in different VPC to transit gateway to same VPC to CUDN VM - expected to succeed
* eni-srcdst-disable DaemonSet should configure new nodes to be traffic next hop
    * Connectivity from EC2 to CUDN VM and CUDN VM to EC2 after DaemonSet is instantiated on cluster that has not had `disable_src_dst_check.sh` run - expected to succeed
    * Connectivity from EC2 to CUDN VM and CUDN VM to EC2 should be maintained during all of the following scenarios
        * MachinePool scale up - expected to succeed
        * Cluster upgrade - expected to succeed
