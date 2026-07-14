#!/bin/bash

# ============================================================================
# Kubernetes Base Node Bootstrap Script
# Author: Raj Patel
#
# Purpose:
#   This script prepares a Debian/Ubuntu based Linux machine for Kubernetes.
#   It installs and configures:
#     - Kubernetes repository
#     - kubelet, kubeadm, kubectl
#     - containerd.io
#     - kernel modules
#     - sysctl networking settings
#     - swap disablement
#     - UFW firewall rules based on node role and selected CNI
#
# After running this script:
#   - Use "kubeadm init" on a control-plane node
#   - Use "kubeadm join" on a worker node
#
# Supported usage:
#   Interactive:
#     sudo ./base-kubernetes.sh
#
#   Non-interactive:
#     sudo ./base-kubernetes.sh control-plane flannel
#     sudo ./base-kubernetes.sh worker flannel
#     sudo ./base-kubernetes.sh control-plane calico-vxlan
#     sudo ./base-kubernetes.sh worker calico-vxlan
#     sudo ./base-kubernetes.sh control-plane calico-bgp
#     sudo ./base-kubernetes.sh worker calico-bgp
#     sudo ./base-kubernetes.sh worker none
#
# Notes:
#   - Change K8S_MINOR_VERSION if you want another Kubernetes minor version.
#   - This script prepares the node only. It does not run kubeadm init/join.
# ============================================================================

set -euo pipefail

K8S_MINOR_VERSION="${K8S_MINOR_VERSION:-v1.36}"
LOG_FILE="/var/log/kubernetes-base-setup.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================================="
echo " Kubernetes Base Node Bootstrap Script"
echo " Log file: $LOG_FILE"
echo "=================================================================="

# ----------------------------------------------------------------------------
# Root check
# ----------------------------------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Please run this script as root or with sudo."
    exit 1
fi

# ----------------------------------------------------------------------------
# OS check
# ----------------------------------------------------------------------------
if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Unable to detect operating system."
    exit 1
fi

. /etc/os-release

if [[ "${ID}" != "debian" && "${ID}" != "ubuntu" ]]; then
    echo "ERROR: This script currently supports Debian and Ubuntu only."
    echo "Detected OS: ${PRETTY_NAME:-unknown}"
    exit 1
fi

echo "--- Detected OS: ${PRETTY_NAME} ---"

# ----------------------------------------------------------------------------
# Read node role and CNI type
# ----------------------------------------------------------------------------
NODE_ROLE="${1:-}"
CNI_TYPE="${2:-}"

if [[ -z "$NODE_ROLE" ]]; then
    echo
    echo "Select Kubernetes node role:"
    echo "1) control-plane"
    echo "2) worker"
    read -rp "Enter choice [1-2]: " ROLE_CHOICE

    case "$ROLE_CHOICE" in
        1)
            NODE_ROLE="control-plane"
            ;;
        2)
            NODE_ROLE="worker"
            ;;
        *)
            echo "ERROR: Invalid node role selection."
            exit 1
            ;;
    esac
fi

case "$NODE_ROLE" in
    master)
        NODE_ROLE="control-plane"
        ;;
    control-plane|worker)
        ;;
    *)
        echo "ERROR: Invalid node role: $NODE_ROLE"
        echo "Allowed values: control-plane, master, worker"
        exit 1
        ;;
esac

if [[ -z "$CNI_TYPE" ]]; then
    echo
    echo "Select CNI type:"
    echo "1) flannel"
    echo "2) calico-vxlan"
    echo "3) calico-bgp"
    echo "4) none"
    read -rp "Enter choice [1-4]: " CNI_CHOICE

    case "$CNI_CHOICE" in
        1)
            CNI_TYPE="flannel"
            ;;
        2)
            CNI_TYPE="calico-vxlan"
            ;;
        3)
            CNI_TYPE="calico-bgp"
            ;;
        4)
            CNI_TYPE="none"
            ;;
        *)
            echo "ERROR: Invalid CNI selection."
            exit 1
            ;;
    esac
fi

case "$CNI_TYPE" in
    flannel|calico-vxlan|calico-bgp|none)
        ;;
    *)
        echo "ERROR: Invalid CNI type: $CNI_TYPE"
        echo "Allowed values: flannel, calico-vxlan, calico-bgp, none"
        exit 1
        ;;
esac

echo
echo "--- Selected Configuration ---"
echo "Node role : $NODE_ROLE"
echo "CNI type  : $CNI_TYPE"
echo "K8s repo  : $K8S_MINOR_VERSION"
echo

# ----------------------------------------------------------------------------
# Update system and install dependencies
# ----------------------------------------------------------------------------
echo "--- Updating system and installing dependencies ---"

apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    ufw

# ----------------------------------------------------------------------------
# Configure Kubernetes repository
# ----------------------------------------------------------------------------
echo "--- Configuring Kubernetes Repository: $K8S_MINOR_VERSION ---"

mkdir -p -m 755 /etc/apt/keyrings
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg

curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR_VERSION}/deb/Release.key" \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat > /etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR_VERSION}/deb/ /
EOF

chmod 644 /etc/apt/sources.list.d/kubernetes.list

# ----------------------------------------------------------------------------
# Configure Docker repository for containerd.io
# ----------------------------------------------------------------------------
echo "--- Configuring Docker Repository for containerd.io ---"

install -m 0755 -d /etc/apt/keyrings
rm -f /etc/apt/keyrings/docker.asc

curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/${ID}
Suites: ${VERSION_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# ----------------------------------------------------------------------------
# Install Kubernetes packages and containerd
# ----------------------------------------------------------------------------
echo "--- Installing kubelet, kubeadm, kubectl, and containerd.io ---"

apt-get update
apt-get install -y kubelet kubeadm kubectl containerd.io

echo "--- Holding Kubernetes packages to prevent accidental upgrades ---"
apt-mark hold kubelet kubeadm kubectl

# ----------------------------------------------------------------------------
# Disable swap
# ----------------------------------------------------------------------------
echo "--- Disabling Swap ---"

swapoff -a

# Comment active swap entries in /etc/fstab if not already commented
sed -i.bak '/[[:space:]]swap[[:space:]]/ s/^\([^#]\)/#\1/' /etc/fstab

# ----------------------------------------------------------------------------
# Enable required kernel modules
# ----------------------------------------------------------------------------
echo "--- Enabling Kernel Modules ---"

cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# ----------------------------------------------------------------------------
# Configure sysctl for Kubernetes networking
# ----------------------------------------------------------------------------
echo "--- Configuring Sysctl Settings ---"

cat > /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# ----------------------------------------------------------------------------
# Configure containerd with systemd cgroup driver
# ----------------------------------------------------------------------------
echo "--- Configuring Containerd ---"

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# kubelet may not fully start until kubeadm init/join is completed,
# but it should be enabled so it starts automatically after reboot.
systemctl enable kubelet

# ----------------------------------------------------------------------------
# Configure UFW firewall
# ----------------------------------------------------------------------------
echo "--- Configuring UFW Firewall ---"

# Always allow SSH first to avoid locking yourself out.
ufw allow 22/tcp comment "SSH"

# --------------------------------------------------------------------------
# Kubernetes control-plane ports
#
# Required for control-plane nodes:
#   6443/tcp       - Kubernetes API Server
#   2379:2380/tcp  - etcd server client API
#   10250/tcp      - Kubelet API
#   10257/tcp      - kube-controller-manager
#   10259/tcp      - kube-scheduler
#
# Note:
#   10251/tcp was used by older kube-scheduler versions and is normally
#   not required for modern Kubernetes versions.
# --------------------------------------------------------------------------

if [[ "$NODE_ROLE" == "control-plane" ]]; then
    echo "--- Opening control-plane ports ---"

    ufw allow 6443/tcp comment "Kubernetes API Server"
    ufw allow 2379:2380/tcp comment "etcd server client API"
    ufw allow 10250/tcp comment "Kubelet API"
    ufw allow 10257/tcp comment "kube-controller-manager"
    ufw allow 10259/tcp comment "kube-scheduler"

    # Uncomment only if using older Kubernetes versions that require it.
    # ufw allow 10251/tcp comment "kube-scheduler old insecure port"

    # Optional:
    # If you plan to run workloads on the control-plane node and expose
    # NodePort services from it, uncomment these lines.
    # ufw allow 30000:32767/tcp comment "NodePort Services TCP"
    # ufw allow 30000:32767/udp comment "NodePort Services UDP"
fi

# --------------------------------------------------------------------------
# Kubernetes worker node ports
#
# Required for worker nodes:
#   10250/tcp          - Kubelet API
#   10256/tcp          - kube-proxy health check
#   30000:32767/tcp    - NodePort Services
#   30000:32767/udp    - NodePort Services
# --------------------------------------------------------------------------

if [[ "$NODE_ROLE" == "worker" ]]; then
    echo "--- Opening worker node ports ---"

    ufw allow 10250/tcp comment "Kubelet API"
    ufw allow 10256/tcp comment "kube-proxy health check"
    ufw allow 30000:32767/tcp comment "NodePort Services TCP"
    ufw allow 30000:32767/udp comment "NodePort Services UDP"
fi

# --------------------------------------------------------------------------
# CNI-specific firewall ports
#
# Flannel:
#   VXLAN backend on Linux commonly uses UDP 8472.
#
# Calico:
#   calico-vxlan uses UDP 4789.
#   calico-bgp uses TCP 179.
#
# Additional Calico notes:
#   If you use Calico IP-in-IP mode, you must allow IP-in-IP protocol 4
#   between nodes. This is not a normal TCP/UDP port.
#
#   If you use Calico WireGuard:
#     IPv4 WireGuard commonly uses UDP 51820.
#     IPv6 WireGuard commonly uses UDP 51821.
#
# Open only what your selected CNI mode requires.
# --------------------------------------------------------------------------

echo "--- Opening CNI-specific ports ---"

case "$CNI_TYPE" in
    flannel)
        ufw allow 8472/udp comment "Flannel VXLAN"
        ;;

    calico-vxlan)
        ufw allow 4789/udp comment "Calico VXLAN"
        ;;

    calico-bgp)
        ufw allow 179/tcp comment "Calico BGP"
        ;;

    none)
        echo "No CNI-specific firewall ports opened."
        ;;

esac

echo "--- Enabling UFW ---"
ufw --force enable

# ----------------------------------------------------------------------------
# Validation
# ----------------------------------------------------------------------------
echo
echo "=================================================================="
echo " Validation"
echo "=================================================================="

echo "--- Kubernetes tools ---"
kubeadm version || true
kubelet --version || true
kubectl version --client || true

echo
echo "--- Container runtime ---"
containerd --version || true
systemctl is-enabled containerd || true
systemctl is-active containerd || true

echo
echo "--- Kernel modules ---"
lsmod | grep -E 'overlay|br_netfilter' || true

echo
echo "--- Sysctl values ---"
sysctl net.bridge.bridge-nf-call-iptables || true
sysctl net.bridge.bridge-nf-call-ip6tables || true
sysctl net.ipv4.ip_forward || true

echo
echo "--- Swap status ---"
swapon --show || true

echo
echo "--- UFW status ---"
ufw status verbose || true

echo
echo "=================================================================="
echo " Setup Complete"
echo "=================================================================="
echo "Node role configured as: $NODE_ROLE"
echo "CNI firewall profile:   $CNI_TYPE"
echo
echo "Next steps:"
if [[ "$NODE_ROLE" == "control-plane" ]]; then
    echo "  1. Initialize cluster using kubeadm init."
    echo "     Example:"
    echo "       kubeadm init --pod-network-cidr=10.244.0.0/16"
    echo
    echo "     Note:"
    echo "       For Flannel, 10.244.0.0/16 is commonly used."
    echo "       For Calico, choose the pod CIDR based on your Calico install method."
    echo
    echo "  2. Configure kubectl for your user."
    echo "  3. Install your selected CNI plugin."
else
    echo "  1. Run the kubeadm join command generated from your control-plane node."
fi
echo
echo "Log saved to: $LOG_FILE"
echo "=================================================================="