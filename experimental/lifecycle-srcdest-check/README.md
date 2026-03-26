
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

The idea is:

1. Create an IAM policy that allows `ec2:ModifyNetworkInterfaceAttribute`, scoped to ENIs tagged for this cluster. :contentReference[oaicite:2]{index=2}
2. Create an IAM role with OIDC trust so a guest-cluster ServiceAccount can assume it. On ROSA HCP, the projected token audience in this flow is `openshift`. :contentReference[oaicite:3]{index=3}
3. Run a DaemonSet on each worker with `hostNetwork: true`, query IMDS for the node ENI ID, and run `aws ec2 modify-network-interface-attribute --no-source-dest-check`. :contentReference[oaicite:4]{index=4}
4. Optionally patch the guest cluster network operator to enable `routeAdvertisements` and FRR support. :contentReference[oaicite:5]{index=5}

## Important caveats

- This approach is currently **experimental** and should not be treated as proven lifecycle guidance yet. :contentReference[oaicite:6]{index=6}
- As written, the DaemonSet handles only the **primary ENI** by taking the first MAC returned from IMDS. Nodes with multiple ENIs would need an extended loop. :contentReference[oaicite:7]{index=7}
- `hostNetwork: true` is intentional here so the pod can reach IMDS at `169.254.169.254` directly from the host network namespace rather than through OVN. The write-up also notes this avoids the IMDSv2 hop-limit issue that can appear from a normal container network namespace. :contentReference[oaicite:8]{index=8}
- The namespace needs both appropriate Pod Security labels and the `hostnetwork` SCC grant. :contentReference[oaicite:9]{index=9}

## Files in this directory

- `namespace.yaml` — dedicated namespace for the DaemonSet
- `serviceaccount.yaml` — ServiceAccount annotated with the IAM role ARN
- `daemonset.yaml` — worker-node DaemonSet that disables Src/Dst check
- `iam-policy.json` — example IAM permissions policy
- `trust-policy.json` — example OIDC trust policy

## Prerequisites

- AWS CLI configured with permissions to create IAM policies and IAM roles
- `oc` logged into the **guest cluster** (not the management cluster)
- your ROSA cluster name
- your AWS account ID
- your cluster OIDC issuer / provider path :contentReference[oaicite:10]{index=10}

## Required placeholders

Before using these files, replace the placeholders below:

- `<account-id>`
- `<cluster-name>`
- `<oidc-provider>`
- `<region>`

If you decide to rename the namespace or ServiceAccount, also update:
- namespace references in all manifests
- the ServiceAccount name in `trust-policy.json`
- the role annotation in `serviceaccount.yaml`

## Example workflow

### 1. Discover the cluster OIDC issuer

```bash
OIDC_ISSUER=$(oc get authentication cluster \
  -o jsonpath='{.spec.serviceAccountIssuer}')
OIDC_PROVIDER=${OIDC_ISSUER#https://}
echo "$OIDC_PROVIDER"
````

The original write-up uses the cluster authentication object and strips the `https://` prefix because IAM expects the bare provider host/path. 

### 2. Create the IAM policy

Edit `iam-policy.json` and replace `<cluster-name>`, then create it:

```bash
aws iam create-policy \
  --policy-name eni-srcdst-disable \
  --policy-document file://iam-policy.json
```

The policy is intended to be scoped by the `kubernetes.io/cluster/<cluster-name>=owned` ENI tag. 

### 3. Create the IAM role and attach the policy

Edit `trust-policy.json` and replace:

* `<account-id>`
* `<oidc-provider>`

Then create the role and attach the policy:

```bash
aws iam create-role \
  --role-name eni-srcdst-disable \
  --assume-role-policy-document file://trust-policy.json

aws iam attach-role-policy \
  --role-name eni-srcdst-disable \
  --policy-arn arn:aws:iam::<account-id>:policy/eni-srcdst-disable
```

The trust policy in the write-up uses `sts:AssumeRoleWithWebIdentity` and the audience `openshift`. 

### 4. Apply the Kubernetes manifests

```bash
oc apply -f namespace.yaml
oc apply -f serviceaccount.yaml
oc apply -f daemonset.yaml
```

### 5. Grant the `hostnetwork` SCC

```bash
oc adm policy add-scc-to-user hostnetwork \
  -z eni-srcdst-disable \
  -n eni-srcdst-disable
```

The original write-up uses the `hostnetwork` SCC rather than `privileged`. 

## Verification

Check that the DaemonSet pods are running:

```bash
oc get pods -n eni-srcdst-disable -o wide
```

Then confirm Src/Dst check is disabled for a target ENI:

```bash
aws ec2 describe-network-interfaces \
  --network-interface-ids <eni-id> \
  --query 'NetworkInterfaces[0].SourceDestCheck'
```

Expected result:

```text
false
```

These are the same basic verification steps shown in the write-up. 

## Optional: enable OVN route advertisements and FRR

Once Src/Dst check is disabled, the write-up suggests patching the network operator like this:

```bash
oc patch network.operator.openshift.io/cluster --type=merge -p '{
  "spec": {
    "defaultNetwork": {
      "ovnKubernetesConfig": {
        "routeAdvertisements": "Enabled"
      }
    },
    "additionalRoutingCapabilities": {
      "providers": ["FRR"]
    }
  }
}'
```

It also suggests checking that the CRD exposes the relevant fields before patching. 

## Known gaps / future work

* Validate worker replacement / scale-up behavior end-to-end
* Validate Route Server behavior specifically
* Decide whether the DaemonSet should iterate over multiple ENIs instead of only the first IMDS MAC
* Confirm whether any cleanup / rollback steps should also be documented

## Safety notes

Please do **not** commit:

* real AWS account IDs
* real OIDC provider values
* real cluster names if you consider them sensitive
* real role ARNs
* real ENI IDs
* raw test output containing environment-specific identifiers