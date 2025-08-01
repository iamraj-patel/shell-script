#!/bin/bash

set -euo pipefail

ADMIN_CONF="/etc/kubernetes/admin.conf"
NODE_NAME=$(hostname)
ETCD_BACKUP_DIR="/root/etcd-backup-$(date +%F-%H%M%S)"

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo)."
    exit 1
fi

echo "Checking for available Kubernetes upgrades..."

UPGRADE_OUTPUT=$(kubeadm upgrade plan --kubeconfig $ADMIN_CONF 2>/dev/null)

CURRENT_VERSION=$(echo "$UPGRADE_OUTPUT" | grep -oP '\[upgrade/versions\] Cluster version: \K([0-9]+\.[0-9]+\.[0-9]+)')
TARGET_VERSION=$(echo "$UPGRADE_OUTPUT" | grep -oP '\[upgrade/versions\] Target version: v\K([0-9]+\.[0-9]+\.[0-9]+)')

if [[ -z "$CURRENT_VERSION" || -z "$TARGET_VERSION" ]]; then
    echo "Could not determine current or target version. Please check kubeadm upgrade plan output."
    exit 1
fi

if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]]; then
    echo "No minor upgrade available. Current version: $CURRENT_VERSION"
    exit 0
fi

echo "Minor upgrade available: $CURRENT_VERSION -> $TARGET_VERSION"

# Backup etcd
echo "Backing up etcd data to $ETCD_BACKUP_DIR ..."
mkdir -p "$ETCD_BACKUP_DIR"
cp -r /var/lib/etcd "$ETCD_BACKUP_DIR"
echo "etcd backup complete."

# Drain the node (using the correct flag)
echo "Draining node $NODE_NAME ..."
kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --kubeconfig $ADMIN_CONF

# Apply the upgrade
echo "Applying Kubernetes control plane upgrade to v$TARGET_VERSION ..."
kubeadm upgrade apply "v$TARGET_VERSION" --yes --kubeconfig $ADMIN_CONF

# Upgrade kubelet and kubectl
echo "Upgrading kubelet and kubectl to v$TARGET_VERSION ..."
apt-get update
apt-get install -y kubelet=$(apt-cache madison kubelet | grep "$TARGET_VERSION" | head -1 | awk '{print $3}') \
                   kubectl=$(apt-cache madison kubectl | grep "$TARGET_VERSION" | head -1 | awk '{print $3}')
systemctl restart kubelet

# Uncordon the node
kubectl uncordon "$NODE_NAME" --kubeconfig $ADMIN_CONF

echo "Kubernetes master node upgrade complete. etcd backup at $ETCD_BACKUP_DIR"
