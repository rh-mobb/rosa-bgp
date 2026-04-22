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
oc delete vm test-vm-b -n cudn2 --ignore-not-found=true
echo "✓ VMs deleted"
echo

# Wait a moment for cleanup
sleep 5

# Apply new VM configurations
echo "Creating VMs with SSH keys..."
oc apply -f tests/test-vm-a.yaml
oc apply -f tests/test-vm-b.yaml
echo "✓ VMs created"
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
echo "Setup complete!"
echo "==================================================================="
echo
echo "SSH private key: $KEYFILE"
echo "SSH public key: ${KEYFILE}.pub"
echo
echo "Infrastructure created:"
echo "  - SSH key secrets in cudn1 and cudn2 namespaces"
echo "  - Jump pods (network-jump) for test SSH access"
echo "  - Test VMs: test-vm-a (cudn1), test-vm-b (cudn2)"
echo
echo "To SSH to VMs:"
echo "  virtctl -n cudn1 ssh -i $KEYFILE fedora@test-vm-a"
echo "  virtctl -n cudn2 ssh -i $KEYFILE fedora@test-vm-b"
echo
echo "Waiting for VMs to be ready (this may take 3-5 minutes)..."
echo "Run: oc get vmi -A"
