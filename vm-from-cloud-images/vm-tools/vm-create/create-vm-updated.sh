#!/bin/bash

# --- UI & Color Definitions ---
C_RESET='\e[0m'
C_BOLD='\e[1m'
C_RED='\e[1;31m'
C_GREEN='\e[1;32m'
C_YELLOW='\e[1;33m'
C_BLUE='\e[1;34m'
C_CYAN='\e[1;36m'
C_MAGENTA='\e[1;35m'

# --- Global Configuration ---
POOL_DIR="/var/lib/libvirt/images"
NETWORK="Private-Network"

# --- Root Check ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${C_RED}❌ This script must be run as root (sudo)${C_RESET}"
   exit 1
fi

# --- Interactive Prompts ---
echo -e "${C_CYAN}======================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}    KVM/QEMU VM Deployment Wizard    ${C_RESET}"
echo -e "${C_CYAN}======================================${C_RESET}"
echo -e "${C_BOLD}Select the OS to deploy:${C_RESET}"
echo -e "  ${C_BLUE}1)${C_RESET} Debian 13"
echo -e "  ${C_BLUE}2)${C_RESET} AlmaLinux 10"
echo -e "  ${C_BLUE}3)${C_RESET} Rocky Linux 10"

echo -ne "${C_YELLOW}Enter choice (1-3): ${C_RESET}"
read OS_CHOICE

case $OS_CHOICE in
   1)
       OS_TYPE="debian"
       BASE_IMG="/home/raj/Downloads/cloud-images/debian-13.qcow2"
       VARIANT="debian13"
       echo -e "${C_GREEN}✔ Selected: Debian 13${C_RESET}"
       ;;
   2)
       OS_TYPE="almalinux"
       BASE_IMG="/home/raj/Downloads/cloud-images/AlmaLinux-10.qcow2"
       if osinfo-query os | grep -q "almalinux10"; then VARIANT="almalinux10"; else VARIANT="almalinux9"; fi
       echo -e "${C_GREEN}✔ Selected: AlmaLinux 10${C_RESET}"
       ;;
   3)
       OS_TYPE="rocky"
       BASE_IMG="/home/raj/Downloads/cloud-images/RockyLinux-10.qcow2"
       if osinfo-query os | grep -q "rocky10"; then VARIANT="rocky10"; else VARIANT="rocky9"; fi
       echo -e "${C_GREEN}✔ Selected: Rocky Linux 10${C_RESET}"
       ;;
   *)
       echo -e "${C_RED}❌ Invalid choice. Exiting.${C_RESET}"
       exit 1
       ;;
esac

echo -e "${C_CYAN}--------------------------------------${C_RESET}"
echo -ne "${C_YELLOW}Enter VM Name:${C_RESET} "
read VM_NAME
if [ -z "$VM_NAME" ]; then
   echo -e "${C_RED}❌ VM Name is required. Exiting.${C_RESET}"
   exit 1
fi

echo -ne "${C_YELLOW}Enter CPU Cores [Default: 2]:${C_RESET} "
read VM_CPU
VM_CPU=${VM_CPU:-2}

echo -ne "${C_YELLOW}Enter RAM in MB [Default: 2048]:${C_RESET} "
read VM_MEM
VM_MEM=${VM_MEM:-2048}

echo -ne "${C_YELLOW}Enter Disk Size (e.g., 25G) [Default: 25G]:${C_RESET} "
read VM_SIZE
VM_SIZE=${VM_SIZE:-25G}

# Auto-append 'G' if the user only types a number (e.g., "30" becomes "30G")
if [[ "$VM_SIZE" =~ ^[0-9]+$ ]]; then
   VM_SIZE="${VM_SIZE}G"
fi

# Check if VM already exists
if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
   echo -e "${C_RED}⚠  Error: VM '$VM_NAME' already exists.${C_RESET}"
   exit 1
fi

# Check if Base Image exists
if [ ! -f "$BASE_IMG" ]; then
   echo -e "${C_RED}❌ Base image not found at: $BASE_IMG${C_RESET}"
   exit 1
fi

TMP_DATA=$(mktemp /tmp/user-data-$VM_NAME.XXXXXX)
trap 'rm -f "$TMP_DATA"' EXIT

echo -e "\n${C_MAGENTA}🚀 Starting Deployment:${C_RESET} ${C_BOLD}$VM_NAME${C_RESET} ${C_CYAN}($VM_CPU vCPU, $VM_MEM MB RAM, Disk: $VM_SIZE)${C_RESET}\n"

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
echo -e "${C_BLUE}💾 Creating layered disk image...${C_RESET}"
qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$POOL_DIR/$VM_NAME.qcow2" "$VM_SIZE" > /dev/null 2>&1
echo -e "${C_GREEN}✔  Disk created successfully.${C_RESET}\n"

# ==========================================
# 3. Launch the VM
# ==========================================
echo -e "${C_BLUE}🛠  Provisioning via virt-install...${C_RESET}"

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
       echo -e "${C_GREEN}✔ Configuration finished. Starting VM...${C_RESET}"
       virsh start "$VM_NAME" > /dev/null 2>&1
   else
       echo -e "${C_GREEN}✔ Configuration finished. VM is already booting...${C_RESET}"
   fi
fi

# ==========================================
# 4. IP Discovery & Wait Loop
# ==========================================
if [ "$OS_TYPE" == "debian" ]; then
   echo -ne "${C_CYAN}⏳ Waiting for network and Guest Agent${C_RESET}"
   MAX_RETRIES=30
   COUNT=0

   while [ $COUNT -lt $MAX_RETRIES ]; do
       IP=$(virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
       AGENT_STATUS=$(virsh qemu-agent-command "$VM_NAME" '{"execute":"guest-ping"}' 2>/dev/null)

       if [ ! -z "$IP" ] && [[ "$AGENT_STATUS" == *"return"* ]]; then
           echo -e "\n\n${C_GREEN}✅ VM is Online!${C_RESET}"
           echo -e "${C_GREEN}╭──────────────────────────────────────────╮${C_RESET}"
           echo -e "${C_GREEN}│${C_RESET} ${C_BOLD}Name:${C_RESET}          $VM_NAME"
           echo -e "${C_GREEN}│${C_RESET} ${C_BOLD}IP Address:${C_RESET}    $IP"
           echo -e "${C_GREEN}│${C_RESET} ${C_BOLD}Guest Agent:${C_RESET}   Active"
           echo -e "${C_GREEN}│${C_RESET} ${C_BOLD}SSH Command:${C_RESET}   ${C_CYAN}ssh raj@$IP${C_RESET}"
           echo -e "${C_GREEN}╰──────────────────────────────────────────╯${C_RESET}"
           exit 0
       fi
        
       printf "${C_CYAN}.${C_RESET}"
       sleep 5
       ((COUNT++))
   done
   echo -e "\n${C_YELLOW}⚠  Timeout: VM started but IP/Agent not detected yet. Check 'virsh list' later.${C_RESET}"

else
   echo -ne "${C_CYAN}⏳ Fetching IP Address${C_RESET}"
   for i in {1..12}; do
       IP=$(virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
       if [ ! -z "$IP" ]; then
           echo -e "\n\n${C_GREEN}🚀 $VM_NAME is READY!${C_RESET}"
           echo -e "${C_GREEN}╭──────────────────────────────────────────╮${C_RESET}"
           echo -e "${C_GREEN}│${C_RESET} ${C_BOLD}Hostname:${C_RESET}      $VM_NAME"
           echo -e "${C_GREEN}│${C_RESET} ${C_BOLD}IP Address:${C_RESET}    $IP"
           echo -e "${C_GREEN}│${C_RESET} ${C_BOLD}SSH Command:${C_RESET}   ${C_CYAN}ssh raj@$IP${C_RESET}"
           echo -e "${C_GREEN}╰──────────────────────────────────────────╯${C_RESET}"
           ssh-keygen -R "$IP" >/dev/null 2>&1
           exit 0
       fi
       printf "${C_CYAN}.${C_RESET}"
       sleep 5
   done
   echo -e "\n${C_YELLOW}⚠  Timeout: IP not detected yet. Check 'virsh domifaddr $VM_NAME' later.${C_RESET}"
fi
