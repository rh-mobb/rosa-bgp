
# Experimental: ROSA HCP ENI source/destination check automation

This directory contains an **experimental / unvalidated** approach for automatically disabling AWS EC2 **Source/Destination Check** on ROSA HCP worker-node ENIs by using a Kubernetes DaemonSet. The goal is to avoid having to manually re-disable the setting after worker lifecycle events such as scale-up or replacement. :contentReference[oaicite:0]{index=0}

## Status

This is **not a validated procedure** yet.

Current status:
- generated write-up / draft manifests
- needs end-to-end validation
- not yet confirmed with Route Server behavior
- shared for future testing and iteration

The original write-up explicitly says the instructions **need to be verified**. :contentReference[oaicite:1]{index=1}

## What this does

This automation provides two complementary lifecycle features:

### 1. Dynamic ENI Configuration and BGP Peer Creation (DaemonSet)

1. Create an IAM policy that allows `ec2:ModifyNetworkInterfaceAttribute`, scoped to ENIs tagged for this cluster. :contentReference[oaicite:2]{index=2}
2. Create an IAM role with OIDC trust so a guest-cluster ServiceAccount can assume it. On ROSA HCP, the projected token audience in this flow is `openshift`. :contentReference[oaicite:3]{index=3}
3. Run a DaemonSet on each worker with `hostNetwork: true`, query IMDS for the node ENI ID, and run `aws ec2 modify-network-interface-attribute --no-source-dest-check`. :contentReference[oaicite:4]{index=4}
4. Automatically create AWS VPC Route Server BGP peers for each router node when it comes online
5. Optionally patch the guest cluster network operator to enable `routeAdvertisements` and FRR support. :contentReference[oaicite:5]{index=5}

### 2. Stale BGP Peer Cleanup (CronJob)

When router nodes are deleted or replaced (with new IPs), their BGP peers remain as orphaned resources in AWS. A periodic CronJob (runs every 15 minutes) automatically:
1. Queries all Route Server peers tagged as managed by the daemonset
2. Queries all active router node IPs from EC2
3. Deletes peers whose IPs don't match any active nodes (with 30-minute age threshold for safety)

## Important caveats

- This approach is currently **experimental** and should not be treated as proven lifecycle guidance yet. :contentReference[oaicite:6]{index=6}
- As written, the DaemonSet handles only the **primary ENI** by taking the first MAC returned from IMDS. Nodes with multiple ENIs would need an extended loop. :contentReference[oaicite:7]{index=7}
- `hostNetwork: true` is intentional here so the pod can reach IMDS at `169.254.169.254` directly from the host network namespace rather than through OVN. The write-up also notes this avoids the IMDSv2 hop-limit issue that can appear from a normal container network namespace. :contentReference[oaicite:8]{index=8}
- The namespace needs both appropriate Pod Security labels and the `hostnetwork` SCC grant. :contentReference[oaicite:9]{index=9}

## Files in this directory

### Kubernetes Manifests
- `namespace.yaml` — dedicated namespace for the DaemonSet and CronJob
- `serviceaccount.yaml` — ServiceAccount annotated with the IAM role ARN (templated)
- `daemonset.yaml` — worker-node DaemonSet that disables Src/Dst check and creates BGP peers (templated)
- `cleanup-cronjob.yaml` — CronJob that periodically cleans up stale BGP peers (templated)

### Terraform Configuration
- `../../eni-srcdst-iam.tf` — IAM policy and role with OIDC trust (automatically integrated with Terraform)

### Deployment Scripts
- `deploy.sh` — automated deployment script that handles variable substitution and OpenShift configuration
- `cleanup-script.sh` — standalone BGP peer cleanup script for manual testing (optional)

### Reference Files (not used by automated workflow)
- `iam-policy.json` — example IAM permissions policy (reference only)
- `trust-policy.json` — example OIDC trust policy (reference only)

## Prerequisites

- Terraform initialized in the project root
- AWS CLI configured with permissions (used by Terraform for IAM resources)
- `oc` CLI installed

## Automated Workflow

This automation has been integrated into the main Terraform configuration. Follow these steps:

### 1. Deploy infrastructure with Terraform

From the project root directory:

```bash
terraform apply
```

This creates:
- ROSA HCP cluster with VPC Route Server
- IAM policy scoped to ENIs tagged `kubernetes.io/cluster/<cluster-name>=owned`
- IAM role with OIDC trust for the `eni-srcdst-disable` ServiceAccount
- All networking and BGP resources

The IAM resources are defined in `../../eni-srcdst-iam.tf` and automatically reference the ROSA cluster's OIDC provider.

### 2. Log into the ROSA cluster

```bash
oc login $(terraform output -raw rosa_api_url) \
  -u cluster-admin \
  -p $(terraform output -raw rosa_cluster_admin_password)
```

### 3. Deploy the ENI automation DaemonSet

Run the automated deployment script:

```bash
./experimental/lifecycle-srcdest-check/deploy.sh
```

The script automatically:
1. Validates prerequisites (oc login, terraform state)
2. Retrieves IAM role ARN and AWS region from Terraform outputs
3. Substitutes values into Kubernetes manifests
4. Applies namespace, ServiceAccount, and DaemonSet
5. Grants the `hostnetwork` SCC to the ServiceAccount
6. Displays deployment status and verification instructions 

## Verification

### Check DaemonSet Status

Verify the DaemonSet is running on all worker nodes (should have 3 pods for 3 router nodes):

```bash
oc get daemonset -n eni-srcdst-disable
oc get pods -n eni-srcdst-disable -o wide
```

### Check Pod Logs

View logs from a DaemonSet pod to confirm successful ENI modification:

```bash
oc logs -n eni-srcdst-disable -l app=eni-srcdst-disable -c disable-srcdst
```

Expected output should show: `Disabling SrcDst check on eni-XXXXXXXXX`

### Verify Source/Destination Check is Disabled

Get an ENI ID from a worker node and verify the setting:

```bash
NODE_IP=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
ENI_ID=$(aws ec2 describe-network-interfaces \
  --filters Name=private-ip-address,Values=$NODE_IP \
  --query 'NetworkInterfaces[0].NetworkInterfaceId' \
  --output text)

aws ec2 describe-network-interfaces \
  --network-interface-ids $ENI_ID \
  --query 'NetworkInterfaces[0].SourceDestCheck'
```

Expected result: `false` 

### Verify BGP Peer Creation

Check that BGP peers were created for each router node:

```bash
# List all daemonset-managed peers
aws ec2 describe-route-server-peers \
  --query 'RouteServerPeers[?Tags[?Key==`managed-by` && Value==`daemonset`]].[RouteServerPeerId,PeerAddress,State,CreationTime]' \
  --output table
```

Expected: 2 peers per router node (one per Route Server endpoint in the node's subnet)

## BGP Peer Cleanup

The deployment includes an automatic cleanup CronJob that runs every 15 minutes to remove stale BGP peers from deleted or replaced nodes.

### How Cleanup Works

The CronJob:
1. Queries EC2 for all active router node IPs (tagged with `bgp_router=true`)
2. Queries Route Server for all peers tagged `managed-by=daemonset`
3. Deletes peers whose IPs don't match any active nodes
4. Enforces a 30-minute minimum age to prevent race conditions

### Safety Mechanisms

- **Minimum Age Check**: Only deletes peers older than 30 minutes
- **Dry-Run Mode**: Can be enabled for testing without actual deletions
- **Concurrency Control**: Prevents overlapping cleanup runs
- **State Filtering**: Skips peers already in `deleted` state
- **Tag Validation**: Only processes peers tagged `managed-by=daemonset`

### Verify CronJob Status

```bash
# Check CronJob configuration
oc get cronjob bgp-peer-cleanup -n eni-srcdst-disable

# View recent jobs
oc get jobs -n eni-srcdst-disable -l app=bgp-peer-cleanup

# View latest job logs
LATEST_JOB=$(oc get jobs -n eni-srcdst-disable -l app=bgp-peer-cleanup --sort-by=.status.startTime -o jsonpath='{.items[-1].metadata.name}')
oc logs job/$LATEST_JOB -n eni-srcdst-disable
```

### Manual Cleanup Testing

Test the cleanup logic manually before waiting for the scheduled run:

```bash
# Option 1: Trigger a one-time job from the CronJob
oc create job --from=cronjob/bgp-peer-cleanup manual-cleanup -n eni-srcdst-disable

# Option 2: Run the standalone script locally (requires AWS credentials)
cd experimental/bgp-node-lifecycle
export CLUSTER_ID=$(cd ../.. && terraform output -raw rosa_cluster_id)
export AWS_DEFAULT_REGION=us-east-1
export DRY_RUN=true  # Set to false for actual deletion
./cleanup-script.sh
```

### Troubleshooting Cleanup

**Issue: Peers not being deleted**

Check the minimum age threshold:
```bash
oc get cronjob bgp-peer-cleanup -n eni-srcdst-disable \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="MIN_AGE_MINUTES")].value}'
```

Temporarily lower for testing:
```bash
oc set env cronjob/bgp-peer-cleanup MIN_AGE_MINUTES=5 -n eni-srcdst-disable
```

**Issue: Permission denied**

Verify the ServiceAccount has the necessary IAM permissions:
```bash
# Check IAM role annotation
oc get sa eni-srcdst-disable -n eni-srcdst-disable \
  -o jsonpath='{.metadata.annotations}'

# Test AWS credentials in a pod
oc run -it --rm aws-test --image=public.ecr.aws/aws-cli/aws-cli:latest \
  --serviceaccount=eni-srcdst-disable -n eni-srcdst-disable \
  -- aws sts get-caller-identity
```

**Issue: CronJob not running**

Check if suspended:
```bash
oc get cronjob bgp-peer-cleanup -n eni-srcdst-disable \
  -o jsonpath='{.spec.suspend}'
```

If suspended, unsuspend:
```bash
oc patch cronjob bgp-peer-cleanup -n eni-srcdst-disable \
  -p '{"spec":{"suspend":false}}'
```

### Disable Cleanup (If Needed)

To temporarily stop cleanup while keeping other functionality:

```bash
# Suspend the CronJob
oc patch cronjob bgp-peer-cleanup -n eni-srcdst-disable \
  -p '{"spec":{"suspend":true}}'

# Or delete it entirely
oc delete cronjob bgp-peer-cleanup -n eni-srcdst-disable
```

To re-enable, run `deploy.sh` again or manually apply `cleanup-cronjob.yaml`.

## Complete the BGP Setup

After the ENI automation is deployed, continue with the BGP and CUDN configuration from the main project:

```bash
# Configure FRR for BGP peering (waits for router nodes to be ready)
./oc-cudn-run1.sh

# Apply CUDN and route advertisement configs
oc apply -f yamls/
```

The `oc-cudn-run1.sh` script handles:
- Enabling OVN route advertisements
- Enabling FRR routing capabilities
- Configuring BGP peering between router nodes and VPC Route Server endpoints

See the main project [CLAUDE.md](../../CLAUDE.md) for complete deployment instructions. 

## Known gaps / future work

* Validate worker replacement / scale-up behavior end-to-end
* Validate Route Server behavior specifically
* Decide whether the DaemonSet should iterate over multiple ENIs instead of only the first IMDS MAC
* Consider adding Prometheus metrics for cleanup job (peers deleted, errors, duration)
* Consider adding alerting/notifications for cleanup failures

## Safety notes

Please do **not** commit:

* real AWS account IDs
* real OIDC provider values
* real cluster names if you consider them sensitive
* real role ARNs
* real ENI IDs
* raw test output containing environment-specific identifiers