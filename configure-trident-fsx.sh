#!/bin/bash
set -e

# Script to configure NetApp Trident CSI driver with FSx for ONTAP
# This script:
# 1. Installs the certified Trident operator
# 2. Deploys TridentOrchestrator
# 3. Configures backend with FSx credentials from Terraform
# 4. Creates and sets default StorageClass

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Configuring NetApp Trident with FSx for ONTAP ==="
echo

# Check prerequisites
if ! command -v oc &> /dev/null; then
    echo "ERROR: 'oc' command not found. Please install OpenShift CLI."
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo "ERROR: 'terraform' command not found."
    exit 1
fi

# Verify we're logged into the cluster
if ! oc whoami &> /dev/null; then
    echo "ERROR: Not logged into OpenShift cluster. Please run 'oc login' first."
    exit 1
fi

# Get FSx configuration from Terraform outputs
echo "Retrieving FSx configuration from Terraform..."
cd "$PROJECT_ROOT"

FSX_ENABLED=$(terraform output -json | jq -r '.fsx_ontap_filesystem_id.value != null')
if [ "$FSX_ENABLED" != "true" ]; then
    echo "ERROR: FSx ONTAP is not enabled or not deployed. Set enable_fsx_ontap=true and run terraform apply."
    exit 1
fi

FSX_SVM_MGMT_ENDPOINT=$(terraform output -raw fsx_ontap_svm_management_endpoint)
FSX_SVM_PASSWORD=$(terraform output -raw fsx_ontap_svm_admin_password)
FSX_SVM_NAME=$(terraform output -raw fsx_ontap_svm_name)

if [ -z "$FSX_SVM_MGMT_ENDPOINT" ] || [ -z "$FSX_SVM_PASSWORD" ] || [ -z "$FSX_SVM_NAME" ]; then
    echo "ERROR: Failed to retrieve FSx configuration from Terraform outputs"
    exit 1
fi

echo "FSx SVM Management Endpoint: $FSX_SVM_MGMT_ENDPOINT"
echo "FSx SVM Name: $FSX_SVM_NAME"
echo

# Step 1: Install NetApp Trident Operator
echo "=== Step 1: Installing NetApp Trident Operator ==="
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-operators
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: trident-operator
  namespace: openshift-operators
spec:
  channel: stable
  name: trident-operator
  source: certified-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

echo "Waiting for Trident operator to be installed..."
for i in {1..60}; do
    if oc get csv -n openshift-operators 2>/dev/null | grep -q "trident-operator.*Succeeded"; then
        echo "✓ Trident operator installed successfully"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "ERROR: Timeout waiting for Trident operator installation"
        oc get csv -n openshift-operators
        exit 1
    fi
    echo -n "."
    sleep 5
done
echo

# Step 2: Deploy TridentOrchestrator
echo "=== Step 2: Deploying TridentOrchestrator ==="
cat <<EOF | oc apply -f -
apiVersion: trident.netapp.io/v1
kind: TridentOrchestrator
metadata:
  name: trident
  namespace: openshift-operators
spec:
  IPv6: false
  debug: false
  nodePrep:
  - iscsi
  imageRegistry: ''
  k8sTimeout: 30
  namespace: trident
  silenceAutosupport: false
EOF

echo "Waiting for Trident namespace to be created..."
for i in {1..30}; do
    if oc get namespace trident &>/dev/null; then
        echo "✓ Trident namespace created"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: Timeout waiting for trident namespace"
        exit 1
    fi
    sleep 2
done

echo "Waiting for TridentOrchestrator to be ready..."
for i in {1..120}; do
    STATUS=$(oc get tridentorchestrator trident -n openshift-operators -o jsonpath='{.status.status}' 2>/dev/null || echo "")
    if [ "$STATUS" = "Installed" ]; then
        echo "✓ TridentOrchestrator is ready"
        break
    fi
    if [ $i -eq 120 ]; then
        echo "ERROR: Timeout waiting for TridentOrchestrator to be ready"
        oc get tridentorchestrator trident -n openshift-operators -o yaml
        exit 1
    fi
    echo -n "."
    sleep 5
done
echo

# Verify Trident pods are running
echo "Verifying Trident pods..."
oc wait --for=condition=Ready pods -l app=controller.csi.trident.netapp.io -n trident --timeout=300s
echo "✓ Trident controller pods are ready"
echo

# Step 3: Configure FSx Backend
echo "=== Step 3: Configuring FSx ONTAP Backend ==="

# Create Secret with FSx credentials
echo "Creating backend secret with FSx credentials..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: backend-fsx-ontap-san-secret
  namespace: trident
type: Opaque
stringData:
  username: vsadmin
  password: '$FSX_SVM_PASSWORD'
EOF
echo "✓ Backend secret created"

# Create TridentBackendConfig
echo "Creating TridentBackendConfig..."
cat <<EOF | oc apply -f -
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: fsx-ontap-san
  namespace: trident
spec:
  backendName: fsx-ontap-san
  managementLIF: $FSX_SVM_MGMT_ENDPOINT
  credentials:
    name: backend-fsx-ontap-san-secret
  storageDriverName: ontap-san-economy
  svm: $FSX_SVM_NAME
  version: 1
EOF

echo "Waiting for TridentBackendConfig to be bound..."
for i in {1..60}; do
    PHASE=$(oc get tridentbackendconfig fsx-ontap-san -n trident -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$PHASE" = "Bound" ]; then
        echo "✓ TridentBackendConfig is bound"
        break
    fi
    if [ "$PHASE" = "Failed" ]; then
        echo "ERROR: TridentBackendConfig failed to bind"
        oc get tridentbackendconfig fsx-ontap-san -n trident -o yaml
        exit 1
    fi
    if [ $i -eq 60 ]; then
        echo "ERROR: Timeout waiting for TridentBackendConfig to be bound"
        oc get tridentbackendconfig fsx-ontap-san -n trident -o yaml
        exit 1
    fi
    echo -n "."
    sleep 5
done
echo

# Step 4: Create and Set Default StorageClass
echo "=== Step 4: Creating StorageClass ==="

# Remove default annotation from existing StorageClasses
echo "Removing default annotation from existing StorageClasses..."
EXISTING_DEFAULT=$(oc get storageclass -o json | jq -r '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true") | .metadata.name')
if [ -n "$EXISTING_DEFAULT" ]; then
    for sc in $EXISTING_DEFAULT; do
        echo "  Removing default from: $sc"
        oc patch storageclass "$sc" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
    done
fi

# Create new StorageClass
echo "Creating Trident StorageClass..."
cat <<EOF | oc apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: trident-csi-san
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.trident.netapp.io
parameters:
  backendType: "ontap-san-economy"
  provisioningType: thin
  snapshots: 'true'
  storagePools: "fsx-ontap-san:.*"
  fsType: "ext4"
mountOptions:
  - discard
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF
echo "✓ StorageClass 'trident-csi-san' created and set as default"
echo

# Verification
echo "=== Verification ==="
echo
echo "Default StorageClass:"
oc get storageclass -o custom-columns=NAME:.metadata.name,DEFAULT:.metadata.annotations."storageclass\.kubernetes\.io/is-default-class"
echo
echo "Trident Backend Status:"
oc get tridentbackendconfig -n trident
echo
echo "Trident Version:"
oc get tridentversion -n trident
echo

echo "=== Configuration Complete! ==="
echo
echo "You can now create PVCs using the 'trident-csi-san' StorageClass."
echo
echo "Example PVC:"
echo "---"
cat <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: trident-csi-san
EOF
