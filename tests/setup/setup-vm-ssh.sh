#!/bin/bash
# Setup SSH access for test VMs
# Generates an SSH keypair and updates VM configurations to use it

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
            runcmd:
              - [systemctl, enable, httpd]
              - [systemctl, start, httpd]
              - [/bin/sh, -c, 'echo "<h1>Test VM A - CUDN1</h1><p>Network: cluster-udn-prod (10.100.0.0/16)</p><p>IP: \$(hostname -I)</p>" > /var/www/html/index.html']
EOF

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
            runcmd:
              - [systemctl, enable, httpd]
              - [systemctl, start, httpd]
              - [/bin/sh, -c, 'echo "<h1>Test VM B - CUDN2</h1><p>Network: cluster-udn-second (10.101.0.0/16)</p><p>IP: \$(hostname -I)</p>" > /var/www/html/index.html']
EOF

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

echo "==================================================================="
echo "Setup complete!"
echo "==================================================================="
echo
echo "SSH private key: $KEYFILE"
echo "SSH public key: ${KEYFILE}.pub"
echo
echo "To SSH to VMs:"
echo "  virtctl -n cudn1 ssh -i $KEYFILE fedora@test-vm-a"
echo "  virtctl -n cudn2 ssh -i $KEYFILE fedora@test-vm-b"
echo
echo "Waiting for VMs to be ready (this may take 3-5 minutes)..."
echo "Run: oc get vmi -A"
