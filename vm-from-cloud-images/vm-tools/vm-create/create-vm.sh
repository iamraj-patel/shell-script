#!/bin/bash

# --- Global Configuration ---
POOL_DIR="/var/lib/libvirt/images"
NETWORK="Private-Network"

# --- Root Check ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root (sudo)"
   exit 1
fi

# --- Interactive Prompts ---
echo "======================================"
echo "    KVM/QEMU VM Deployment Wizard     "
echo "======================================"
echo "Select the OS to deploy:"
echo "1) Debian 13"
echo "2) AlmaLinux 10"
echo "3) Rocky Linux 10"
read -p "Enter choice (1-3): " OS_CHOICE

case $OS_CHOICE in
    1)
        OS_TYPE="debian"
        BASE_IMG="/home/raj/Downloads/cloud-images/debian-13.qcow2"
        VARIANT="debian13"
        echo "Selected: Debian 13"
        ;;
    2)
        OS_TYPE="almalinux"
        BASE_IMG="/home/raj/Downloads/cloud-images/AlmaLinux-10.qcow2"
        if osinfo-query os | grep -q "almalinux10"; then VARIANT="almalinux10"; else VARIANT="almalinux9"; fi
        echo "Selected: AlmaLinux 10"
        ;;
    3)
        OS_TYPE="rocky"
        BASE_IMG="/home/raj/Downloads/cloud-images/RockyLinux-10.qcow2"
        if osinfo-query os | grep -q "rocky10"; then VARIANT="rocky10"; else VARIANT="rocky9"; fi
        echo "Selected: Rocky Linux 10"
        ;;
    *)
        echo "❌ Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "--------------------------------------"
read -p "Enter VM Name: " VM_NAME
if [ -z "$VM_NAME" ]; then
    echo "❌ VM Name is required. Exiting."
    exit 1
fi

read -p "Enter CPU Cores [Default: 2]: " VM_CPU
VM_CPU=${VM_CPU:-2}

read -p "Enter RAM in MB [Default: 2048]: " VM_MEM
VM_MEM=${VM_MEM:-2048}

read -p "Enter Disk Size (e.g., 25G) [Default: 25G]: " VM_SIZE
VM_SIZE=${VM_SIZE:-25G}

# Auto-append 'G' if the user only types a number (e.g., "30" becomes "30G")
if [[ "$VM_SIZE" =~ ^[0-9]+$ ]]; then
    VM_SIZE="${VM_SIZE}G"
fi

# Check if VM already exists
if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    echo "⚠️  Error: VM '$VM_NAME' already exists."
    exit 1
fi

# Check if Base Image exists
if [ ! -f "$BASE_IMG" ]; then
    echo "❌ Base image not found at: $BASE_IMG"
    exit 1
fi

TMP_DATA=$(mktemp /tmp/user-data-$VM_NAME.XXXXXX)
trap 'rm -f "$TMP_DATA"' EXIT

echo "🚀 Starting Deployment: $VM_NAME ($VM_CPU vCPU, $VM_MEM MB RAM, Disk: $VM_SIZE)"

# ==========================================
# 1. Cloud-init Configuration
# ==========================================
if [ "$OS_TYPE" == "debian" ]; then
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
  - fastfetch

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

else
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
fi

# ==========================================
# 2. Storage
# ==========================================
echo "💾 Creating layered disk image..."
qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$POOL_DIR/$VM_NAME.qcow2" "$VM_SIZE"

# ==========================================
# 3. Launch the VM
# ==========================================
echo "🛠️ Provisioning via virt-install..."

if [ "$OS_TYPE" == "debian" ]; then
    virt-install \
      --name "$VM_NAME" \
      --memory "$VM_MEM" \
      --vcpus "$VM_CPU" \
      --os-variant "$VARIANT" \
      --boot uefi \
      --machine q35 \
      --disk path="$POOL_DIR/$VM_NAME.qcow2",device=disk,bus=virtio \
      --network network="$NETWORK",model=virtio \
      --cloud-init user-data="$TMP_DATA" \
      --graphics vnc,listen=0.0.0.0 \
      --noautoconsole \
      --quiet \
      --import
else
    # AlmaLinux / Rocky Linux specific launch
    virt-install \
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
      
    # Safe Start (No --quiet flag to avoid version errors)
    if ! virsh list | grep -q "$VM_NAME"; then
        echo "✅ Configuration finished. Starting VM..."
        virsh start "$VM_NAME"
    else
        echo "✅ Configuration finished. VM is already booting..."
    fi
fi

# ==========================================
# 4. IP Discovery & Wait Loop
# ==========================================
if [ "$OS_TYPE" == "debian" ]; then
    echo -n "⏳ Waiting for network and Guest Agent"
    MAX_RETRIES=30
    COUNT=0

    while [ $COUNT -lt $MAX_RETRIES ]; do
        IP=$(virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
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

else
    echo -n "⏳ Fetching IP Address"
    for i in {1..12}; do
        IP=$(virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
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
    echo -e "\n⚠️  Timeout: IP not detected yet. Check 'virsh domifaddr $VM_NAME' later."
fi

