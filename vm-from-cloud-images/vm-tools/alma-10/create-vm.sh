#!/bin/bash

# Configuration
VM_NAME=$1
# Updated path as per your request
BASE_IMG="/home/raj/Downloads/cloud-images/AlmaLinux-10.qcow2"
POOL_DIR="/var/lib/libvirt/images"
TMP_DATA="/tmp/user-data-$VM_NAME"

if [ -z "$VM_NAME" ]; then
    echo "Usage: $0 <vm-name>"
    exit 1
fi

# Ensure permissions for the Downloads path
chmod +x /home/raj /home/raj/Downloads /home/raj/Downloads/cloud-images 2>/dev/null

echo "🚀 Deploying UEFI AlmaLinux 10 VM: $VM_NAME..."

# 1. Create the dynamic Cloud-init config
cat <<EOF > "$TMP_DATA"
#cloud-config
hostname: $VM_NAME
fqdn: $VM_NAME.local
ssh_pwauth: true

# Package management
package_update: true
package_upgrade: true
package_reboot_if_required: true

# Added bash-completion and qemu-guest-agent
packages:
  - bash-completion
  - qemu-guest-agent
  - curl
  - vim

users:
  - name: raj
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: "YourSecurePasswordHere"
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAGbAwADv9elOFsGLEXIhitUJrSaHyiPl5byE75+SSMN Test-Computer

growpart:
  mode: auto
  devices: ['/']

# Using write_files for aliases (Most reliable for RHEL/Alma 10)
write_files:
  - path: /etc/profile.d/custom_aliases.sh
    owner: root:root
    permissions: '0644'
    content: |
      alias c='clear'
      alias cls='clear'

runcmd:
  # Ensure Guest Agent starts immediately
  - systemctl enable --now qemu-guest-agent
  # Fix SELinux labels for the new alias file
  - restorecon -v /etc/profile.d/custom_aliases.sh
EOF

# 2. Create a Linked Clone (25GB)
sudo qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$POOL_DIR/$VM_NAME.qcow2" 25G

# 3. Launch the VM with UEFI and Q35 chipset
sudo virt-install \
  --name "$VM_NAME" \
  --memory 2048 \
  --vcpus 2 \
  --os-variant almalinux10 \
  --boot uefi \
  --machine q35 \
  --disk path="$POOL_DIR/$VM_NAME.qcow2",format=qcow2 \
  --import \
  --network network=Private-Network \
  --cloud-init user-data="$TMP_DATA" \
  --graphics none \
  --noautoconsole

# 4. Cleanup temp file
rm "$TMP_DATA"

echo "⏳ Waiting for $VM_NAME to initialize and Guest Agent to start..."

# 5. IP Discovery Loop (Matches your Debian 13 script functionality)
while true; do
    IP=$(sudo virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    if [ ! -z "$IP" ]; then
        # Check if Guest Agent is responding before declaring success
        if sudo virsh guestinfo "$VM_NAME" >/dev/null 2>&1; then
            echo -e "\n✅ $VM_NAME is Ready!"
            echo "IP Address: $IP"
            echo "Guest Agent: Connected"
            echo "SSH: ssh raj@$IP"
            break
        fi
    fi
    printf "."
    sleep 5
done
