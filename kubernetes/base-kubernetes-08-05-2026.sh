#!/bin/bash

################################################################################
# Kubernetes Debian Host Preparation Script
#
# Prepares a Debian-based system for Kubernetes using kubeadm.
#
# Installs:
#   - kubeadm
#   - kubelet
#   - kubectl
#   - containerd
#   - cri-tools
#
# Configures:
#   - Kubernetes repositories
#   - Containerd
#   - crictl
#   - Kernel modules
#   - Sysctl settings
#   - UFW firewall
#   - Kubectl completion
#
# Ready for:
#   - kubeadm init
#   - kubeadm join
################################################################################

set -euo pipefail

########################################
# Variables
########################################

K8S_VERSION="v1.36"
K8S_REPO="https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/"
K8S_KEY="${K8S_REPO}Release.key"

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

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root or with sudo."
    exit 1
fi

########################################
# Install Base Packages
########################################

echo "--- Installing Dependencies ---"

apt-get update

apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    ufw \
    cri-tools \
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
# Kubernetes Repository
########################################

echo "--- Configuring Kubernetes Repository ---"

mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL "${K8S_KEY}" | \
gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat > /etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${K8S_REPO} /
EOF

chmod 644 /etc/apt/sources.list.d/kubernetes.list

########################################
# Docker Repository
########################################

echo "--- Configuring Docker Repository ---"

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

########################################
# Install Kubernetes Components
########################################

echo "--- Installing Kubernetes Components ---"

apt-get update

apt-get install -y \
    kubelet \
    kubeadm \
    kubectl \
    containerd.io

apt-mark hold kubelet kubeadm kubectl

########################################
# Disable Swap
########################################

echo "--- Disabling Swap ---"

swapoff -a

sed -i '/ swap / s/^/#/' /etc/fstab

########################################
# Kernel Modules
########################################

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
    modprobe "$module"
done

echo "--- Validating Modules ---"

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
        echo "PASS: ${module}"
    else
        echo "FAIL: ${module}"
        exit 1
    fi
done

########################################
# Sysctl Configuration
########################################

echo "--- Configuring Sysctl ---"

cat > /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
EOF

sysctl --system

########################################
# Containerd Configuration
########################################

echo "--- Configuring Containerd ---"

mkdir -p /etc/containerd

containerd config default > /etc/containerd/config.toml

sed -i \
's/SystemdCgroup = false/SystemdCgroup = true/g' \
/etc/containerd/config.toml

systemctl enable --now containerd

########################################
# crictl Configuration
########################################

echo "--- Configuring crictl ---"

cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

########################################
# Enable Kubelet
########################################

echo "--- Enabling kubelet ---"

systemctl enable kubelet

########################################
# Kubectl Completion
########################################

echo "--- Configuring kubectl completion ---"

kubectl completion bash \
> /etc/bash_completion.d/kubectl

cat > /etc/profile.d/kubectl-alias.sh <<EOF
alias k=kubectl
complete -o default -F __start_kubectl k
EOF

chmod 644 /etc/profile.d/kubectl-alias.sh

########################################
# UFW Forwarding Policy
########################################

echo "--- Configuring UFW Forwarding Policy ---"

sed -i \
's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' \
/etc/default/ufw

########################################
# Firewall Rules
########################################

echo "--- Configuring UFW Firewall ---"

ufw allow 22/tcp

# Kubernetes API
ufw allow 6443/tcp

# etcd
ufw allow 2379:2380/tcp

# Controller Manager
ufw allow 10257/tcp

# Scheduler
ufw allow 10259/tcp

# Kubelet
ufw allow 10250/tcp

# Calico BGP
ufw allow 179/tcp

# VXLAN
ufw allow 4789/udp

# Flannel VXLAN
ufw allow 8472/udp

# NodePort Services
ufw allow 30000:32767/tcp

ufw --force enable
ufw reload

########################################
# Version Information
########################################

echo
echo "=================================================="
echo " Installed Versions"
echo "=================================================="

kubeadm version || true
kubectl version --client || true
kubelet --version || true
containerd --version || true
crictl --version || true

########################################
# Validation
########################################

echo
echo "=================================================="
echo " Validation"
echo "=================================================="

echo "--- Swap ---"

if swapon --show | grep -q .; then
    echo "FAIL: Swap still enabled"
    exit 1
else
    echo "PASS: Swap disabled"
fi

echo "--- Sysctl ---"

[[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]] \
&& echo "PASS: IP Forwarding Enabled" \
|| exit 1

echo "--- Containerd ---"

systemctl is-active --quiet containerd \
&& echo "PASS: Containerd Active" \
|| exit 1

systemctl is-enabled --quiet containerd \
&& echo "PASS: Containerd Enabled" \
|| exit 1

echo "--- Kubelet ---"

systemctl is-enabled --quiet kubelet \
&& echo "PASS: Kubelet Enabled" \
|| exit 1

echo "--- CRI ---"

crictl info >/dev/null 2>&1 \
&& echo "PASS: CRI Connected" \
|| exit 1

########################################
# Completion Message
########################################

echo
echo "=================================================="
echo " Kubernetes Host Ready"
echo "=================================================="
echo "Hostname : $(hostname)"
echo "OS       : $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
echo "Kernel   : $(uname -r)"
echo
echo "Next Steps:"
echo
echo "Create Control Plane:"
echo "kubeadm init --pod-network-cidr=<POD_CIDR>"
echo
echo "Join Existing Cluster:"
echo "kubeadm join <CONTROL_PLANE>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>"
echo
echo "Install your preferred CNI:"
echo "  - Calico"
echo "  - Cilium"
echo "  - Flannel"
echo
echo "Validation Status: PASS"
echo "=================================================="
