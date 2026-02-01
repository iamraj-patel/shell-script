#!/bin/bash

# Configuration
VM_NAME=$1
BASE_IMG="/home/raj/Downloads/cloud-images/AlmaLinux-10.qcow2"
POOL_DIR="/var/lib/libvirt/images"
TMP_DATA="/tmp/user-data-$VM_NAME"

if [ -z "$VM_NAME" ]; then
    echo "Usage: $0 <vm-name>"
    exit 1
fi

chmod +x /home/raj /home/raj/Downloads /home/raj/Downloads/cloud-images 2>/dev/null

echo "🚀 Deploying UEFI AlmaLinux 10 VM: $VM_NAME..."

# 1. Create the Cloud-init config
cat <<EOF > "$TMP_DATA"
#cloud-config
hostname: $VM_NAME
fqdn: $VM_NAME.local
ssh_pwauth: true

package_update: true
package_upgrade: true

packages:
  - bash-completion
  - qemu-guest-agent
  - firewalld
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

  - name: ansible
    groups: wheel
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

runcmd:
  # 1. Start Guest Agent
  - systemctl enable --now qemu-guest-agent
  # 2. Firewall: Offline modifications
  - firewall-offline-cmd --zone=public --add-service=ssh
  - firewall-offline-cmd --zone=public --remove-service=cockpit
  - firewall-offline-cmd --zone=public --remove-service=dhcpv6-client
  - systemctl enable --now firewalld
  # 3. Firewall: Live cleanup (Ensures Cockpit is stripped even if defaults re-added it)
  - firewall-cmd --permanent --zone=public --remove-service=cockpit
  - firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client
  - firewall-cmd --reload
  # 4. System: Mask Cockpit so it can NEVER start
  - systemctl stop cockpit.socket || true
  - systemctl disable --now cockpit.socket || true
  - systemctl mask cockpit.socket || true
  - systemctl mask cockpit.service || true
  # 5. Final Touches
  - systemctl enable --now sshd
  - restorecon -v /etc/profile.d/custom_aliases.sh
EOF

# 2. Create Clone
sudo qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$POOL_DIR/$VM_NAME.qcow2" 25G

# 3. Launch VM
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

rm "$TMP_DATA"

echo "⏳ Waiting for VM Network and Config to finish..."

# 4. Discovery Loop
while true; do
    IP=$(sudo virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    
    if [ ! -z "$IP" ]; then
        if nc -z -w 2 "$IP" 22 2>/dev/null; then
            echo -e "\n\n✅ $VM_NAME is FULLY configured!"
            echo "-------------------------------------------"
            echo "IP Address : $IP"
            echo "Firewall   : Active (SSH Only)"
            echo "Cockpit    : Removed from Firewall & Masked"
            echo "SSH Command: ssh raj@$IP"
            echo "-------------------------------------------"
            break
        fi
    fi
    
    printf "."
    sleep 3
done
