# This script works for Debain based distribution where it installs and configures basic Kubernetes packages like Kubectl, Kubeadm and Kubelet
# as well as Containerd.io by configuring necessary repositories, it configures firewall by adding specific port related master and worker node
# communication at the end it enabled all of the necessary services after which we just need to initialize cluster and confiure CNI.

#!/bin/bash

# Exit on error
set -e

echo "--- Updating system and installing dependencies ---"
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg ufw

# 1. Setup Kubernetes Repository (v1.35)
echo "--- Configuring Kubernetes Repository ---"
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list

# 2. Setup Docker/Containerd Repository
echo "--- Configuring Containerd Repository ---"
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# 3. Install Packages
echo "--- Installing Kubeadm, Kubelet, Kubectl, and Containerd ---"
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl containerd.io
sudo apt-mark hold kubelet kubeadm kubectl

# 4. System Prerequisites (Swap & Kernel Modules)
echo "--- Disabling Swap ---"
sudo swapoff -a
sudo sed -i '/swap/s/^/#/' /etc/fstab

echo "--- Enabling Kernel Modules ---"
sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

echo "--- Configuring Sysctl ---"
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# 5. Configure Containerd (SystemdCgroup)
echo "--- Configuring Containerd ---"
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

# 6. Firewall Configuration (UFW)
echo "--- Configuring UFW Firewall for Master and Worker roles ---"
sudo ufw allow 22/tcp # Ensure SSH stays open

# Control Plane (Master) Ports
sudo ufw allow 6443/tcp
sudo ufw allow 2379:2380/tcp
sudo ufw allow 10251/tcp
sudo ufw allow 10259/tcp
sudo ufw allow 10257/tcp
sudo ufw allow 8472/udp

# Common & Worker Ports
sudo ufw allow 179/tcp
sudo ufw allow 10250/tcp
sudo ufw allow 4789/udp
sudo ufw allow 30000:32767/tcp

sudo ufw --force enable

echo "--- Setup Complete! ---"
echo "Check containerd status: systemctl status containerd"
