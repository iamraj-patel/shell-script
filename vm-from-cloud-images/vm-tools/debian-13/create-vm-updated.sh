#!/bin/bash

# --- Configuration ---
BASE_IMG="/home/raj/Downloads/cloud-images/debian-13.qcow2"
POOL_DIR="/var/lib/libvirt/images"
NETWORK="Private-Network"

# Default Resources (can be overridden by arguments)
VM_NAME=$1
VM_MEM=${2:-2048}  # Default 2GB
VM_CPU=${3:-2}     # Default 2 Cores
VM_SIZE="25G"

# Usage Check
if [ -z "$VM_NAME" ]; then
    echo "❌ Usage: $0 <vm-name> [memory_mb] [vcpus]"
    echo "Example: $0 debian-web 4096 4"
    exit 1
fi

# Root Check
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root (sudo)"
   exit 1
fi

# Check if VM already exists
if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    echo "⚠️  Error: VM '$VM_NAME' already exists."
    exit 1
fi

TMP_DATA=$(mktemp /tmp/user-data-$VM_NAME.XXXXXX)

echo "🚀 Starting Deployment: $VM_NAME ($VM_CPU vCPU, $VM_MEM MB RAM)"

# 1. Create Cloud-init Config
cat <<EOF > "$TMP_DATA"
#cloud-config
hostname: $VM_NAME
manage_etc_hosts: true
ssh_pwauth: true

locale: en_US.UTF-8
timezone: UTC

package_update: true
package_upgrade: true

packages:
  - sudo
  - curl
  - qemu-guest-agent
  - locales-all
  - vim
  - net-tools

users:
  - name: raj
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: "$6$rounds=4096$virt-secret$6P/NlC.YyWd..." # Recommend using hashed passwords
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAGbAwADv9elOFsGLEXIhitUJrSaHyiPl5byE75+SSMN Test-Computer
    sudo: ALL=(ALL) NOPASSWD:ALL
  
  - name: ansible
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: "YourSecurePasswordHere"
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIl8FP8+zqdP/7A11l9XkUjdZrXXTTX2swfSyrBUAkJs raj@ansible
    sudo: ALL=(ALL) NOPASSWD:ALL

write_files:
  - path: /etc/profile.d/custom_aliases.sh
    owner: root:root
    permissions: '0644'
    content: |
      alias c='clear'
      alias cls='clear'
      alias ll='ls -la'

runcmd:
  - [ systemctl, enable, --now, qemu-guest-agent ]
  - [ localectl, set-locale, LANG=en_US.UTF-8 ]
EOF

# 2. Prepare Storage
echo "💾 Creating layered disk image..."
qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$POOL_DIR/$VM_NAME.qcow2" "$VM_SIZE"

# 3. Launch the VM
echo "🛠️ Provisioning via virt-install..."
virt-install \
  --name "$VM_NAME" \
  --memory "$VM_MEM" \
  --vcpus "$VM_CPU" \
  --os-variant debian13 \
  --boot uefi \
  --machine q35 \
  --disk path="$POOL_DIR/$VM_NAME.qcow2",device=disk,bus=virtio \
  --network network="$NETWORK",model=virtio \
  --cloud-init user-data="$TMP_DATA" \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole \
  --quiet \
  --import

# Cleanup temp file
rm "$TMP_DATA"

# 4. Wait Loop for IP and Guest Agent
echo -n "⏳ Waiting for network and Guest Agent"
MAX_RETRIES=30
COUNT=0

while [ $COUNT -lt $MAX_RETRIES ]; do
    IP=$(virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    
    # Check if Agent is alive
    AGENT_STATUS=$(virsh qemu-agent-command "$VM_NAME" '{"execute":"guest-ping"}' 2>/dev/null)

    if [ ! -z "$IP" ] && [[ "$AGENT_STATUS" == *"return"* ]]; then
        echo -e "\n\n✅ VM is Online!"
        echo "-------------------------------"
        echo "Name:         $VM_NAME"
        echo "IP Address:   $IP"
        echo "Guest Agent:  Active"
        echo "SSH Command:  ssh raj@$IP"
        echo "-------------------------------"
        exit 0
    fi
    
    printf "."
    sleep 5
    ((COUNT++))
done

echo -e "\n⚠️  Timeout: VM started but IP/Agent not detected yet. Check 'virsh list' later."

