#!/bin/bash

set -euo pipefail

NODE_NAME=$(hostname)

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo)."
    exit 1
fi

# Get the target version (from the control plane node)
TARGET_VERSION=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.nodeInfo.kubeletVersion}' | sed 's/v//')

echo "Target version for upgrade: $TARGET_VERSION"

# Drain the node (using the correct flag)
echo "Draining worker node $NODE_NAME ..."
kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data

# Upgrade kubeadm, kubelet, and kubectl
echo "Upgrading kubeadm, kubelet, and kubectl to $TARGET_VERSION ..."
apt-get update
apt-get install -y kubeadm=$(apt-cache madison kubeadm | grep "$TARGET_VERSION" | head -1 | awk '{print $3}') \
                   kubelet=$(apt-cache madison kubelet | grep "$TARGET_VERSION" | head -1 | awk '{print $3}') \
                   kubectl=$(apt-cache madison kubectl | grep "$TARGET_VERSION" | head -1 | awk '{print $3}')
systemctl restart kubelet

# Upgrade node components
echo "Running kubeadm upgrade node ..."
kubeadm upgrade node

# Uncordon the node
kubectl uncordon "$NODE_NAME"

echo "Worker node $NODE_NAME upgrade complete."
