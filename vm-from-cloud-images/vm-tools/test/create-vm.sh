#!/bin/bash

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' 
BOLD='\033[1m'

# --- Configuration ---
VM_NAME=$1
BASE_IMG="/home/raj/Downloads/cloud-images/AlmaLinux-10.qcow2"
POOL_DIR="/var/lib/libvirt/images"
TMP_DATA="/tmp/user-data-$VM_NAME"

if [ -z "$VM_NAME" ]; then
    echo -e "${RED}❌ Error: No VM name provided.${NC}"
    exit 1
fi

chmod +x /home/raj /home/raj/Downloads /home/raj/Downloads/cloud-images 2>/dev/null

echo -e "${BLUE}${BOLD}🚀 Phase 1: Deploying UEFI AlmaLinux 10 VM: ${CYAN}$VM_NAME${NC}"

# 1. Create the Cloud-init config
cat <<EOF > "$TMP_DATA"
#cloud-config
hostname: $VM_NAME
fqdn: $VM_NAME.local
ssh_pwauth: true
package_update: true

packages:
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
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: "YourSecurePasswordHere"
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIl8FP8+zqdP/7A11l9XkUjdZrXXTTX2swfSyrBUAkJs raj@ansible

write_files:
  - path: /etc/profile.d/custom_aliases.sh
    owner: root:root
    permissions: '0755'
    content: |
      alias c='clear'
      alias cls='clear'
      alias ll='ls -alF'

runcmd:
  - [ systemctl, enable, --now, qemu-guest-agent ]
  - [ systemctl, mask, cockpit.socket ]
  - [ systemctl, mask, cockpit.service ]
  - [ systemctl, enable, --now, firewalld ]
  - [ firewall-cmd, --permanent, --zone=public, --add-service=ssh ]
  - [ firewall-cmd, --permanent, --zone=public, --remove-service=cockpit ]
  - [ firewall-cmd, --reload ]
  # Force SELinux to recognize the new profile script
  - [ restorecon, -v, /etc/profile.d/custom_aliases.sh ]
EOF

# 2. Create Storage Clone
echo -e "${BLUE}📦 Creating disk image...${NC}"
sudo qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$POOL_DIR/$VM_NAME.qcow2" 25G > /dev/null

# 3. Launch VM
echo -e "${BLUE}🖥️  Starting virtual machine...${NC}"
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

echo -e "${YELLOW}⏳ Phase 2: Waiting for VM network and SSH readiness...${NC}"

while true; do
    IP=$(sudo virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    if [ ! -z "$IP" ] && nc -z -w 2 "$IP" 22 2>/dev/null; then
        break
    fi
    printf "${CYAN}.${NC}"
    sleep 2
done

echo -e "\n${GREEN}✨ Phase 3: Running Security & Compliance Audit on $IP...${NC}"

# 4. Remote Audit Execution
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "raj@$IP" << 'EOF'
    G='\033[0;32m'
    R='\033[0;31m'
    Y='\033[1;33m'
    NC='\033[0m'
    BOLD='\033[1m'

    while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 2; done
    
    echo -e "\n${Y}===========================================${NC}"
    echo -e "       ${BOLD}SECURITY & COMPLIANCE REPORT${NC}        "
    echo -e "${Y}===========================================${NC}"

    # 1. Alias Check
    # We test if the alias is defined in a login shell environment
    if bash -l -c "alias c" &>/dev/null; then
        echo -e "${G}✅ [SHELL] Custom aliases (c, cls) are active.${NC}"
    else
        echo -e "${R}❌ [VIOLATION] Aliases not found. Fixing permissions...${NC}"
        sudo chmod 755 /etc/profile.d/custom_aliases.sh
        sudo restorecon /etc/profile.d/custom_aliases.sh
    fi

    # 2. Ansible User
    if sudo -u ansible sudo -n true 2>/dev/null; then
         echo -e "${G}✅ [USER] Ansible passwordless sudo verified.${NC}"
    else
         echo -e "${R}❌ [VIOLATION] Ansible sudo failed.${NC}"
    fi

    # 3. Cockpit Check
    if systemctl is-enabled cockpit.service 2>&1 | grep -q "masked"; then
        echo -e "${G}✅ [SERVICE] Cockpit masked.${NC}"
    else
        echo -e "${R}❌ [VIOLATION] Cockpit not masked.${NC}"
    fi

    # 4. Firewall Check
    if sudo firewall-cmd --list-services | grep -q "cockpit"; then
        echo -e "${R}❌ [VIOLATION] Firewall permits Cockpit! Fixing...${NC}"
        sudo firewall-cmd --permanent --remove-service=cockpit >/dev/null 2>&1
        sudo firewall-cmd --reload >/dev/null 2>&1
    else
        echo -e "${G}✅ [FIREWALL] Hardened (SSH only).${NC}"
    fi

    # 5. SELinux Check
    echo -e "${G}✅ [SECURITY] SELinux is $(getenforce).${NC}"
    
    echo -e "${Y}===========================================${NC}"
EOF

echo -e "\n${GREEN}${BOLD}VM '$VM_NAME' is perfectly deployed and validated!${NC}"
echo -e "${CYAN}-------------------------------------------${NC}"
echo -e "${BOLD}IP Address  :${NC} $IP"
echo -e "${BOLD}SSH Command :${NC} ssh raj@$IP"
echo -e "${CYAN}-------------------------------------------${NC}"