#!/bin/bash

# --- Configuration ---
BASE_IMG="/home/raj/Downloads/cloud-images/RockyLinux-10.qcow2"
POOL_DIR="/var/lib/libvirt/images"
NETWORK="Private-Network"

VM_NAME=$1
VM_MEM=${2:-2048}
VM_CPU=${3:-2}
VM_SIZE="25G"

if [ -z "$VM_NAME" ]; then
    echo "❌ Usage: $0 <vm-name> [memory_mb] [vcpus]"
    exit 1
fi

if sudo virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    echo "⚠️  Error: VM '$VM_NAME' already exists."
    exit 1
fi

TMP_DATA=$(mktemp /tmp/user-data-$VM_NAME.XXXXXX)
trap 'sudo rm -f "$TMP_DATA"' EXIT

echo "🚀 Deploying UEFI Rocky Linux 10: $VM_NAME..."

# Variant fallback
if osinfo-query os | grep -q "rocky10"; then
    VARIANT="rocky10"
else
    VARIANT="rocky9"
fi

# 1. Cloud-init Configuration
cat <<EOF > "$TMP_DATA"
#cloud-config
hostname: $VM_NAME
fqdn: $VM_NAME.local
manage_etc_hosts: true
ssh_pwauth: true

package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - firewalld
  - curl
  - vim
  - bash-completion

users:
  - name: raj
    groups: wheel
    shell: /bin/bash
    lock_passwd: false
    passwd: "YourSecurePasswordHere"
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAGbAwADv9elOFsGLEXIhitUJrSaHyiPl5byE75+SSMN Test-Computer
    sudo: ALL=(ALL) NOPASSWD:ALL

write_files:
  - path: /etc/profile.d/custom_aliases.sh
    content: |
      alias c='clear'
      alias cls='clear'

runcmd:
  # Force hostname persistence
  - hostnamectl set-hostname $VM_NAME
  - echo "$VM_NAME" > /etc/hostname
  # Guest Agent
  - [ systemctl, enable, --now, qemu-guest-agent ]
  # Firewall Logic
  - firewall-offline-cmd --zone=public --add-service=ssh
  - firewall-offline-cmd --zone=public --remove-service=cockpit
  - firewall-offline-cmd --zone=public --remove-service=dhcpv6-client
  - [ systemctl, enable, --now, firewalld ]
  - firewall-cmd --permanent --zone=public --remove-service=cockpit
  - firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client
  - firewall-cmd --reload
  - [ systemctl, mask, --now, cockpit.socket ]
  - [ systemctl, mask, --now, cockpit.service ]
  - restorecon -Rv /etc/profile.d/
  # SIGNAL COMPLETION
  - sync
  - poweroff
EOF

# 2. Storage
sudo qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$POOL_DIR/$VM_NAME.qcow2" "$VM_SIZE"

# 3. Launch with --wait
echo "🛠️  Provisioning (Background updates)..."
sudo virt-install \
  --name "$VM_NAME" \
  --memory "$VM_MEM" \
  --vcpus "$VM_CPU" \
  --os-variant "$VARIANT" \
  --boot uefi \
  --machine q35 \
  --disk path="$POOL_DIR/$VM_NAME.qcow2",bus=virtio \
  --network network="$NETWORK",model=virtio \
  --cloud-init user-data="$TMP_DATA" \
  --graphics none \
  --noautoconsole \
  --import \
  --wait -1

# 4. Safe Start (No --quiet flag to avoid version errors)
if ! sudo virsh list | grep -q "$VM_NAME"; then
    echo "✅ Configuration finished. Starting VM..."
    sudo virsh start "$VM_NAME"
else
    echo "✅ Configuration finished. VM is already booting..."
fi

# 5. IP Discovery
echo -n "⏳ Fetching IP Address"
for i in {1..12}; do
    IP=$(sudo virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    if [ ! -z "$IP" ]; then
        echo -e "\n\n🚀 $VM_NAME is READY!"
        echo "-------------------------------------------"
        echo "IP Address : $IP"
        echo "Hostname   : $VM_NAME"
        echo "SSH Command: ssh raj@$IP"
        echo "-------------------------------------------"
        ssh-keygen -R "$IP" >/dev/null 2>&1
        exit 0
    fi
    printf "."
    sleep 5
done

