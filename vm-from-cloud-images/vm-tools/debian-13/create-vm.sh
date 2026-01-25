#!/bin/bash

# Configuration
VM_NAME=$1
BASE_IMG="/home/raj/Downloads/cloud-images/debian-13.qcow2"
POOL_DIR="/var/lib/libvirt/images"
TMP_DATA="/tmp/user-data-$VM_NAME"

if [ -z "$VM_NAME" ]; then
    echo "Usage: $0 <vm-name>"
    exit 1
fi

# Ensure permissions
chmod +x /home/raj /home/raj/Desktop /home/raj/Desktop/vm-tools /home/raj/Desktop/vm-tools/debian-13 2>/dev/null

echo "🚀 Deploying UEFI Debian 13 VM: $VM_NAME..."

# 1. Recreate a clean Cloud-init config
cat <<EOF > "$TMP_DATA"
#cloud-config
hostname: $VM_NAME
ssh_pwauth: true

# Fix Locale errors
locale: en_US.UTF-8
timezone: UTC

# System updates
package_update: true
package_upgrade: true

# Core packages
packages:
  - sudo
  - curl
  - qemu-guest-agent
  - locales-all

# User configuration
users:
  - name: raj
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: "YourSecurePasswordHere"
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAGbAwADv9elOFsGLEXIhitUJrSaHyiPl5byE75+SSMN Test-Computer
    sudo: ALL=(ALL) NOPASSWD:ALL

# System-wide Aliases (Most reliable)
write_files:
  - path: /etc/profile.d/raj_aliases.sh
    owner: root:root
    permissions: '0644'
    content: |
      alias c='clear'
      alias cls='clear'

# Expand disk
growpart:
  mode: auto
  devices: ['/']

runcmd:
  # 1. Ensure QEMU Guest Agent is actually running and enabled
  - systemctl enable --now qemu-guest-agent
  # 2. Fix potential locale issues immediately
  - localectl set-locale LANG=en_US.UTF-8
  # 3. Double check aliases permissions
  - chmod 644 /etc/profile.d/raj_aliases.sh
EOF

# 2. Create the Linked Clone
sudo qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$POOL_DIR/$VM_NAME.qcow2" 25G

# 3. Launch the VM
sudo virt-install \
  --name "$VM_NAME" \
  --memory 1024 \
  --vcpus 1 \
  --os-variant debian13 \
  --boot uefi \
  --machine q35 \
  --disk path="$POOL_DIR/$VM_NAME.qcow2",format=qcow2 \
  --import \
  --network network=Private-Network \
  --cloud-init user-data="$TMP_DATA" \
  --graphics none \
  --noautoconsole

# Cleanup
rm "$TMP_DATA"

echo "⏳ Waiting for $VM_NAME to initialize and Guest Agent to start..."

# Wait Loop for IP and Guest Agent
while true; do
    IP=$(sudo virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    if [ ! -z "$IP" ]; then
        # Check if Guest Agent is responding
        if sudo virsh guestinfo "$VM_NAME" >/dev/null 2>&1; then
            echo -e "\n✅ Debian 13 is Ready!"
            echo "IP Address: $IP"
            echo "Guest Agent: Connected"
            echo "SSH: ssh raj@$IP"
            break
        fi
    fi
    printf "."
    sleep 5
done
