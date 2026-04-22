#!/bin/bash
# Setup SSH access for test VMs
# Generates an SSH keypair and stores it as Kubernetes secrets

set -e

KEYFILE="tests/test-vm-key"

echo "==================================================================="
echo "Setting up SSH access for test VMs"
echo "==================================================================="
echo

# Generate SSH keypair if it doesn't exist
if [ ! -f "$KEYFILE" ]; then
    echo "Generating new SSH keypair..."
    ssh-keygen -t ed25519 -f "$KEYFILE" -N '' -C 'test-vm-access'
    echo "✓ Keypair generated: $KEYFILE"
else
    echo "✓ Using existing keypair: $KEYFILE"
fi

# Read the public key
PUBKEY=$(cat ${KEYFILE}.pub)
echo
echo "Public key: $PUBKEY"
echo

# Create SSH key secrets in both namespaces
echo "Creating SSH key secrets in namespaces..."
for namespace in cudn1 cudn2; do
    oc create secret generic test-vm-ssh-key \
        --from-file=id_ed25519="$KEYFILE" \
        --from-file=id_ed25519.pub="${KEYFILE}.pub" \
        --namespace="$namespace" \
        --dry-run=client -o yaml | oc apply -f -
    echo "✓ Secret created/updated in $namespace"
done
echo

# Update test-vm-a.yaml
echo "Updating test-vm-a.yaml..."
cat > tests/test-vm-a.yaml <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: test-vm-a
  namespace: cudn1
  labels:
    app: test-vm
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: test-vm-a
    spec:
      domain:
        devices:
          disks:
          - disk:
              bus: virtio
            name: containerdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - name: default
            binding:
              name: l2bridge
        resources:
          requests:
            memory: 1Gi
            cpu: 1
      networks:
      - name: default
        pod: {}
      volumes:
      - name: containerdisk
        containerDisk:
          image: quay.io/kubevirt/fedora-cloud-container-disk-demo:latest
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            password: fedora
            chpasswd: { expire: False }
            ssh_pwauth: True
            ssh_authorized_keys:
              - $PUBKEY
            packages:
              - httpd
              - bind-utils
              - nmap-ncat
            runcmd:
              - [systemctl, enable, httpd]
              - [systemctl, start, httpd]
              - [/bin/sh, -c, 'echo "<h1>Test VM A - CUDN1</h1><p>Network: cluster-udn-prod (10.100.0.0/16)</p><p>IP: \$(hostname -I)</p>" > /var/www/html/index.html']
EOF
echo "✓ test-vm-a.yaml created"

# Update test-vm-b.yaml
echo "Updating test-vm-b.yaml..."
cat > tests/test-vm-b.yaml <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: test-vm-b
  namespace: cudn2
  labels:
    app: test-vm
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: test-vm-b
    spec:
      domain:
        devices:
          disks:
          - disk:
              bus: virtio
            name: containerdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - name: default
            binding:
              name: l2bridge
        resources:
          requests:
            memory: 1Gi
            cpu: 1
      networks:
      - name: default
        pod: {}
      volumes:
      - name: containerdisk
        containerDisk:
          image: quay.io/kubevirt/fedora-cloud-container-disk-demo:latest
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            password: fedora
            chpasswd: { expire: False }
            ssh_pwauth: True
            ssh_authorized_keys:
              - $PUBKEY
            packages:
              - httpd
              - bind-utils
              - nmap-ncat
            runcmd:
              - [systemctl, enable, httpd]
              - [systemctl, start, httpd]
              - [/bin/sh, -c, 'echo "<h1>Test VM B - CUDN2</h1><p>Network: cluster-udn-second (10.101.0.0/16)</p><p>IP: \$(hostname -I)</p>" > /var/www/html/index.html']
EOF
echo "✓ test-vm-b.yaml created"

echo "✓ VM configurations updated"
echo

# Delete existing VMs
echo "Deleting existing VMs..."
oc delete vm test-vm-a -n cudn1 --ignore-not-found=true
oc delete vm test-vm-a-sameworker -n cudn1 --ignore-not-found=true
oc delete vm test-vm-a-differentworker -n cudn1 --ignore-not-found=true
oc delete vm test-vm-b -n cudn2 --ignore-not-found=true
echo "✓ VMs deleted"
echo

# Wait a moment for cleanup
sleep 5

# Apply new VM configurations
echo "Creating VMs with SSH keys..."
oc apply -f tests/test-vm-a.yaml
oc apply -f tests/test-vm-b.yaml
echo "✓ test-vm-a and test-vm-b created"
echo

# Wait for test-vm-a to be running so we can get its node
echo "Waiting for test-vm-a to be running..."
oc wait --for=condition=Ready vmi/test-vm-a -n cudn1 --timeout=300s
VM_A_NODE=$(oc get vmi test-vm-a -n cudn1 -o jsonpath='{.status.nodeName}')
echo "✓ test-vm-a is running on node: $VM_A_NODE"
echo

# Create test-vm-a-sameworker on the same node as test-vm-a
echo "Updating test-vm-a-sameworker.yaml..."
cat > tests/test-vm-a-sameworker.yaml <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: test-vm-a-sameworker
  namespace: cudn1
  labels:
    app: test-vm
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: test-vm-a-sameworker
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - $VM_A_NODE
      domain:
        devices:
          disks:
          - disk:
              bus: virtio
            name: containerdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - name: default
            binding:
              name: l2bridge
        resources:
          requests:
            memory: 1Gi
            cpu: 1
      networks:
      - name: default
        pod: {}
      volumes:
      - name: containerdisk
        containerDisk:
          image: quay.io/kubevirt/fedora-cloud-container-disk-demo:latest
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            password: fedora
            chpasswd: { expire: False }
            ssh_pwauth: True
            ssh_authorized_keys:
              - $PUBKEY
            packages:
              - httpd
              - bind-utils
              - nmap-ncat
            runcmd:
              - [systemctl, enable, httpd]
              - [systemctl, start, httpd]
              - [/bin/sh, -c, 'echo "<h1>Test VM A2 - CUDN1</h1><p>Network: cluster-udn-prod (10.100.0.0/16)</p><p>Node: $VM_A_NODE</p><p>IP: \$(hostname -I)</p>" > /var/www/html/index.html']
EOF
echo "✓ test-vm-a-sameworker.yaml created"

# Apply test-vm-a-sameworker
echo "Creating test-vm-a-sameworker on same node as test-vm-a..."
oc apply -f tests/test-vm-a-sameworker.yaml
echo "✓ test-vm-a-sameworker created"
echo

# Create test-vm-a-differentworker on a different node than test-vm-a
echo "Updating test-vm-a-differentworker.yaml..."
cat > tests/test-vm-a-differentworker.yaml <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: test-vm-a-differentworker
  namespace: cudn1
  labels:
    app: test-vm
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: test-vm-a-differentworker
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: kubevirt.io/vm
                operator: In
                values:
                - test-vm-a
            topologyKey: kubernetes.io/hostname
      domain:
        devices:
          disks:
          - disk:
              bus: virtio
            name: containerdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - name: default
            binding:
              name: l2bridge
        resources:
          requests:
            memory: 1Gi
            cpu: 1
      networks:
      - name: default
        pod: {}
      volumes:
      - name: containerdisk
        containerDisk:
          image: quay.io/kubevirt/fedora-cloud-container-disk-demo:latest
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            password: fedora
            chpasswd: { expire: False }
            ssh_pwauth: True
            ssh_authorized_keys:
              - $PUBKEY
            packages:
              - httpd
              - bind-utils
              - nmap-ncat
            runcmd:
              - [systemctl, enable, httpd]
              - [systemctl, start, httpd]
              - [/bin/sh, -c, 'echo "<h1>Test VM A Different Worker - CUDN1</h1><p>Network: cluster-udn-prod (10.100.0.0/16)</p><p>IP: \$(hostname -I)</p>" > /var/www/html/index.html']
EOF
echo "✓ test-vm-a-differentworker.yaml created"

# Apply test-vm-a-differentworker
echo "Creating test-vm-a-differentworker on different node than test-vm-a..."
oc apply -f tests/test-vm-a-differentworker.yaml
echo "✓ test-vm-a-differentworker created"
echo

# Create jump pods for SSH access
echo "Creating jump pods for test infrastructure..."
for namespace in cudn1 cudn2; do
    pod_name="network-jump"
    [ "$namespace" = "cudn2" ] && pod_name="network-jump-cudn2"

    cat <<PODEOF | oc apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $namespace
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: $pod_name
    image: registry.access.redhat.com/ubi9/toolbox:latest
    command: ["sleep", "infinity"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      runAsUser: 1000
    volumeMounts:
    - name: ssh-key
      mountPath: /home/test-user/.ssh
      readOnly: true
  volumes:
  - name: ssh-key
    secret:
      secretName: test-vm-ssh-key
      defaultMode: 0400
PODEOF
    echo "✓ Jump pod created in $namespace"
done

# Wait for jump pods to be ready
echo "Waiting for jump pods to be ready..."
oc wait --for=condition=Ready pod/network-jump -n cudn1 --timeout=60s >/dev/null 2>&1
oc wait --for=condition=Ready pod/network-jump-cudn2 -n cudn2 --timeout=60s >/dev/null 2>&1
echo "✓ Jump pods ready"
echo

echo "==================================================================="
echo "Waiting for all VMs to be ready..."
echo "==================================================================="
echo
echo "Waiting for test-vm-a-sameworker, test-vm-a-differentworker, and test-vm-b..."
oc wait --for=condition=Ready vmi/test-vm-a-sameworker -n cudn1 --timeout=300s >/dev/null 2>&1
oc wait --for=condition=Ready vmi/test-vm-a-differentworker -n cudn1 --timeout=300s >/dev/null 2>&1
oc wait --for=condition=Ready vmi/test-vm-b -n cudn2 --timeout=300s >/dev/null 2>&1
echo "✓ All VMs are ready"
echo

# Verify node placement
VM_A_NODE_FINAL=$(oc get vmi test-vm-a -n cudn1 -o jsonpath='{.status.nodeName}')
VM_A_SAMEWORKER_NODE=$(oc get vmi test-vm-a-sameworker -n cudn1 -o jsonpath='{.status.nodeName}')
VM_A_DIFFERENTWORKER_NODE=$(oc get vmi test-vm-a-differentworker -n cudn1 -o jsonpath='{.status.nodeName}')
VM_B_NODE=$(oc get vmi test-vm-b -n cudn2 -o jsonpath='{.status.nodeName}')

echo "==================================================================="
echo "Setup complete!"
echo "==================================================================="
echo
echo "SSH private key: $KEYFILE"
echo "SSH public key: ${KEYFILE}.pub"
echo
echo "Infrastructure created:"
echo "  - SSH key secrets in cudn1 and cudn2 namespaces"
echo "  - Jump pods (network-jump) for test SSH access"
echo "  - Test VMs:"
echo "    - test-vm-a (cudn1) on node: $VM_A_NODE_FINAL"
echo "    - test-vm-a-sameworker (cudn1) on node: $VM_A_SAMEWORKER_NODE"
echo "    - test-vm-a-differentworker (cudn1) on node: $VM_A_DIFFERENTWORKER_NODE"
echo "    - test-vm-b (cudn2) on node: $VM_B_NODE"
echo

if [ "$VM_A_NODE_FINAL" = "$VM_A_SAMEWORKER_NODE" ]; then
    echo "✓ test-vm-a and test-vm-a-sameworker are on the same node"
else
    echo "⚠ WARNING: test-vm-a and test-vm-a-sameworker are on different nodes!"
fi

if [ "$VM_A_NODE_FINAL" != "$VM_A_DIFFERENTWORKER_NODE" ]; then
    echo "✓ test-vm-a and test-vm-a-differentworker are on different nodes"
else
    echo "⚠ WARNING: test-vm-a and test-vm-a-differentworker are on the same node!"
fi
echo

echo "To SSH to VMs:"
echo "  virtctl -n cudn1 ssh -i $KEYFILE fedora@test-vm-a"
echo "  virtctl -n cudn1 ssh -i $KEYFILE fedora@test-vm-a-sameworker"
echo "  virtctl -n cudn1 ssh -i $KEYFILE fedora@test-vm-a-differentworker"
echo "  virtctl -n cudn2 ssh -i $KEYFILE fedora@test-vm-b"
echo
echo "VM Status:"
oc get vmi -A | grep test-vm
