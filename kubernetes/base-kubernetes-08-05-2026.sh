#!/bin/bash

################################################################################
# Kubernetes Debian Host Preparation Script
#
# Purpose:
#   Prepares a Debian-based host for Kubernetes using kubeadm.
#
# This script installs and configures:
#   - Kubernetes apt repository
#   - Docker/containerd apt repository
#   - kubeadm
#   - kubelet
#   - kubectl
#   - containerd.io
#   - cri-tools
#   - required kernel modules
#   - sysctl networking settings
#   - crictl configuration
#   - UFW firewall rules
#   - kubectl bash completion
#   - validation checks
#
# After completion, the host should be ready for:
#   - kubeadm init
#   - kubeadm join
#   - CNI installation
################################################################################

set -euo pipefail

########################################
# Configuration Variables
########################################

K8S_VERSION="v1.36"
K8S_REPO_URL="https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/"
K8S_RELEASE_KEY_URL="${K8S_REPO_URL}Release.key"

DOCKER_REPO_URL="https://download.docker.com/linux/debian"

K8S_KEYRING="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
DOCKER_KEYRING="/etc/apt/keyrings/docker.asc"

K8S_APT_LIST="/etc/apt/sources.list.d/kubernetes.list"
DOCKER_APT_SOURCES="/etc/apt/sources.list.d/docker.sources"

########################################
# Banner
########################################

echo "=================================================="
echo " Kubernetes Debian Host Preparation Script"
echo " Kubernetes Repository Version: ${K8S_VERSION}"
echo "=================================================="

########################################
# Root Check
########################################

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Please run this script as root or with sudo."
    exit 1
fi

########################################
# OS Detection
########################################

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: /etc/os-release not found. Cannot detect OS."
    exit 1
fi

. /etc/os-release

if [[ "${ID}" != "debian" && "${ID_LIKE:-}" != *"debian"* ]]; then
    echo "WARNING: This script is designed for Debian-based systems."
    echo "Detected OS: ${PRETTY_NAME}"
fi

if [[ -z "${VERSION_CODENAME:-}" ]]; then
    echo "ERROR: VERSION_CODENAME could not be detected from /etc/os-release."
    exit 1
fi

echo "Detected OS: ${PRETTY_NAME}"
echo "Detected Codename: ${VERSION_CODENAME}"

########################################
# Install Base Dependencies
########################################

echo
echo "--- Installing Base Dependencies ---"

apt-get update

apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    ufw \
    vim \
    wget \
    jq \
    dnsutils \
    net-tools \
    htop \
    bash-completion \
    iptables \
    ipvsadm

########################################
# Configure Kubernetes Repository
########################################

echo
echo "--- Configuring Kubernetes Repository: ${K8S_VERSION} ---"

mkdir -p -m 755 /etc/apt/keyrings

rm -f "${K8S_KEYRING}"

curl -fsSL "${K8S_RELEASE_KEY_URL}" | \
    gpg --dearmor -o "${K8S_KEYRING}"

chmod 644 "${K8S_KEYRING}"

cat > "${K8S_APT_LIST}" <<EOF
deb [signed-by=${K8S_KEYRING}] ${K8S_REPO_URL} /
EOF

chmod 644 "${K8S_APT_LIST}"

########################################
# Configure Docker Repository for containerd.io
########################################

echo
echo "--- Configuring Docker Repository for containerd.io ---"

install -m 0755 -d /etc/apt/keyrings

rm -f "${DOCKER_KEYRING}"

curl -fsSL "${DOCKER_REPO_URL}/gpg" \
    -o "${DOCKER_KEYRING}"

chmod a+r "${DOCKER_KEYRING}"

cat > "${DOCKER_APT_SOURCES}" <<EOF
Types: deb
URIs: ${DOCKER_REPO_URL}
Suites: ${VERSION_CODENAME}
Components: stable
Signed-By: ${DOCKER_KEYRING}
EOF

########################################
# Install Kubernetes Components and Container Runtime
########################################

echo
echo "--- Installing kubelet, kubeadm, kubectl, containerd.io, and cri-tools ---"

apt-get update

apt-get install -y \
    kubelet \
    kubeadm \
    kubectl \
    containerd.io \
    cri-tools

echo
echo "--- Holding Kubernetes Package Versions ---"

apt-mark hold kubelet kubeadm kubectl containerd.io

########################################
# Disable Swap
########################################

echo
echo "--- Disabling Swap ---"

swapoff -a

if grep -qE '^[^#].*\sswap\s' /etc/fstab; then
    sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab
    echo "Swap entries in /etc/fstab have been commented."
else
    echo "No active swap entries found in /etc/fstab."
fi

########################################
# Kernel Modules
########################################

echo
echo "--- Configuring Kernel Modules ---"

cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF

for module in \
    overlay \
    br_netfilter \
    ip_vs \
    ip_vs_rr \
    ip_vs_wrr \
    ip_vs_sh \
    nf_conntrack
do
    modprobe "${module}"
done

echo
echo "--- Validating Kernel Modules ---"

for module in \
    overlay \
    br_netfilter \
    ip_vs \
    ip_vs_rr \
    ip_vs_wrr \
    ip_vs_sh \
    nf_conntrack
do
    if lsmod | grep -q "^${module}"; then
        echo "PASS: Kernel module loaded: ${module}"
    else
        echo "FAIL: Kernel module failed to load: ${module}"
        exit 1
    fi
done

########################################
# Sysctl Configuration
########################################

echo
echo "--- Configuring Kubernetes Sysctl Settings ---"

cat > /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

########################################
# Configure containerd
########################################

echo
echo "--- Configuring containerd with SystemdCgroup ---"

mkdir -p /etc/containerd

containerd config default > /etc/containerd/config.toml

sed -i \
    's/SystemdCgroup = false/SystemdCgroup = true/g' \
    /etc/containerd/config.toml

systemctl daemon-reload
systemctl enable --now containerd
systemctl restart containerd

########################################
# Configure crictl
########################################

echo
echo "--- Configuring crictl ---"

cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

########################################
# Enable kubelet
########################################

echo
echo "--- Enabling kubelet ---"

systemctl enable kubelet

########################################
# Kubectl Bash Completion
########################################

echo
echo "--- Configuring kubectl Bash Completion ---"

kubectl completion bash > /etc/bash_completion.d/kubectl

cat > /etc/profile.d/kubectl-alias.sh <<EOF
alias k=kubectl
complete -o default -F __start_kubectl k
EOF

chmod 644 /etc/profile.d/kubectl-alias.sh

########################################
# UFW Forwarding Policy
########################################

echo
echo "--- Configuring UFW Forwarding Policy ---"

if grep -q '^DEFAULT_FORWARD_POLICY=' /etc/default/ufw; then
    sed -i \
        's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' \
        /etc/default/ufw
else
    echo 'DEFAULT_FORWARD_POLICY="ACCEPT"' >> /etc/default/ufw
fi

########################################
# Firewall Rules
########################################

echo
echo "--- Configuring UFW Firewall Rules ---"

# SSH
ufw allow 22/tcp comment "SSH"

# Kubernetes API Server
ufw allow 6443/tcp comment "Kubernetes API Server"

# etcd
ufw allow 2379:2380/tcp comment "Kubernetes etcd"

# kubelet API
ufw allow 10250/tcp comment "Kubelet API"

# kube-controller-manager secure port
ufw allow 10257/tcp comment "Kube Controller Manager"

# kube-scheduler secure port
ufw allow 10259/tcp comment "Kube Scheduler"

# Calico BGP
ufw allow 179/tcp comment "Calico BGP"

# VXLAN, commonly used by Calico/Cilium depending on mode
ufw allow 4789/udp comment "VXLAN"

# Flannel VXLAN
ufw allow 8472/udp comment "Flannel VXLAN"

# NodePort Services
ufw allow 30000:32767/tcp comment "Kubernetes NodePort Services"

ufw --force enable
ufw reload

########################################
# Installed Versions
########################################

echo
echo "=================================================="
echo " Installed Component Versions"
echo "=================================================="

echo
echo "--- kubeadm ---"
kubeadm version || true

echo
echo "--- kubectl ---"
kubectl version --client || true

echo
echo "--- kubelet ---"
kubelet --version || true

echo
echo "--- containerd ---"
containerd --version || true

echo
echo "--- crictl ---"
crictl --version || true

########################################
# Validation
########################################

echo
echo "=================================================="
echo " Kubernetes Host Validation Report"
echo "=================================================="

echo
echo "--- Host Information ---"
echo "Hostname : $(hostname)"
echo "OS       : ${PRETTY_NAME}"
echo "Kernel   : $(uname -r)"
echo "K8s Repo : ${K8S_VERSION}"

echo
echo "--- Swap Validation ---"

if swapon --show | grep -q .; then
    echo "FAIL: Swap is still enabled."
    swapon --show
    exit 1
else
    echo "PASS: Swap is disabled."
fi

echo
echo "--- Sysctl Validation ---"

if [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]]; then
    echo "PASS: net.ipv4.ip_forward is enabled."
else
    echo "FAIL: net.ipv4.ip_forward is not enabled."
    exit 1
fi

if [[ "$(sysctl -n net.bridge.bridge-nf-call-iptables)" == "1" ]]; then
    echo "PASS: net.bridge.bridge-nf-call-iptables is enabled."
else
    echo "FAIL: net.bridge.bridge-nf-call-iptables is not enabled."
    exit 1
fi

if [[ "$(sysctl -n net.bridge.bridge-nf-call-ip6tables)" == "1" ]]; then
    echo "PASS: net.bridge.bridge-nf-call-ip6tables is enabled."
else
    echo "FAIL: net.bridge.bridge-nf-call-ip6tables is not enabled."
    exit 1
fi

echo
echo "--- Service Validation ---"

if systemctl is-active --quiet containerd; then
    echo "PASS: containerd is active."
else
    echo "FAIL: containerd is not active."
    systemctl status containerd --no-pager || true
    exit 1
fi

if systemctl is-enabled --quiet containerd; then
    echo "PASS: containerd is enabled."
else
    echo "FAIL: containerd is not enabled."
    exit 1
fi

if systemctl is-enabled --quiet kubelet; then
    echo "PASS: kubelet is enabled."
else
    echo "FAIL: kubelet is not enabled."
    exit 1
fi

echo
echo "--- CRI Validation ---"

if crictl info > /dev/null 2>&1; then
    echo "PASS: crictl can communicate with containerd."
else
    echo "FAIL: crictl cannot communicate with containerd."
    echo "Check containerd status and /etc/crictl.yaml."
    exit 1
fi

echo
echo "--- UFW Status ---"
ufw status verbose || true

########################################
# Completion Message
########################################

echo
echo "=================================================="
echo " Kubernetes Host Ready"
echo "=================================================="
echo "Hostname : $(hostname)"
echo "OS       : ${PRETTY_NAME}"
echo "Kernel   : $(uname -r)"
echo "K8s Repo : ${K8S_VERSION}"
echo
echo "Next Steps:"
echo
echo "Create a new control plane:"
echo "  kubeadm init --pod-network-cidr=<POD_CIDR>"
echo
echo "Join an existing cluster:"
echo "  kubeadm join <CONTROL_PLANE>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>"
echo
echo "After kubeadm init:"
echo "  Install your CNI plugin, such as Calico, Cilium, or Flannel."
echo
echo "Validation Status: PASS"
echo "=================================================="
