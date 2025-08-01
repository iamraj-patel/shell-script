#!/bin/bash

set -e

# Configuration
DOWNLOAD_DIR="/etc/script/calico"
GITHUB_TAGS_API="https://api.github.com/repos/projectcalico/calico/tags"
MANIFEST_URL_TEMPLATE="https://raw.githubusercontent.com/projectcalico/calico/%s/manifests/calico.yaml"

# Get current Calico version from cluster
CURRENT_VERSION=$(kubectl -n kube-system get daemonset calico-node -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -o 'v[0-9]*\.[0-9]*\.[0-9]*')

if [[ -z "$CURRENT_VERSION" ]]; then
  echo "❗ Could not determine current Calico version."
  exit 1
fi

echo "🔍 Current Calico version: $CURRENT_VERSION"

# Fetch all tags from GitHub
TAGS=$(curl -s "$GITHUB_TAGS_API" | grep '"name":' | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' | sort -Vr)

# Find latest valid version with existing manifest
for VERSION in $TAGS; do
  MANIFEST_URL=$(printf "$MANIFEST_URL_TEMPLATE" "$VERSION")
  if curl --head --silent --fail "$MANIFEST_URL" > /dev/null; then
    LATEST_VERSION="$VERSION"
    break
  fi
done

if [[ -z "$LATEST_VERSION" ]]; then
  echo "❗ No valid Calico release with manifest found."
  exit 1
fi

echo "🌐 Latest valid Calico version with manifest: $LATEST_VERSION"

# Compare with current version
if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
  echo "✅ Calico is already up-to-date."
  exit 0
fi

# Prepare download path
DATE=$(date +%F)
FILENAME="calico-${LATEST_VERSION}-${DATE}.yaml"
DEST="${DOWNLOAD_DIR}/${FILENAME}"

mkdir -p "$DOWNLOAD_DIR"

echo "⬇ Downloading $MANIFEST_URL"
curl -sSfL "$MANIFEST_URL" -o "$DEST"

echo "✅ Calico manifest saved to $DEST"
