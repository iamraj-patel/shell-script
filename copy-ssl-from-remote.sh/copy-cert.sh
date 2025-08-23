#!/bin/bash

# Remote server details
REMOTE_USER="raj"
REMOTE_HOST="resume.raj.cloudns.nz"
SSH_KEY="/home/raj/.ssh/ssl_sync"

# Remote file paths (original)
REMOTE_CERT="/etc/letsencrypt/live/ansible.raj.cloudns.nz/fullchain.pem"
REMOTE_KEY="/etc/letsencrypt/live/ansible.raj.cloudns.nz/privkey.pem"

#REMOTE_CERT="/etc/letsencrypt/live/semaphore.raj.cloudns.nz/fullchain.pem"
#REMOTE_KEY="/etc/letsencrypt/live/semaphore.raj.cloudns.nz/privkey.pem"

# Local destination paths
LOCAL_CERT="/etc/pki/tls/certs/semaphore-fullchain.pem"
LOCAL_KEY="/etc/pki/tls/private/semaphore-privkey.pem"

# Remote temp storage for actual files
REMOTE_TMP_CERT="/tmp/fullchain.pem"
REMOTE_TMP_KEY="/tmp/privkey.pem"

# Step 1: Ensure the actual files are available on the remote server (executed as root)
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "sudo cp -L $REMOTE_CERT $REMOTE_TMP_CERT && sudo cp -L $REMOTE_KEY $REMOTE_TMP_KEY && sudo chmod 644 $REMOTE_TMP_CERT && sudo chmod 644 $REMOTE_TMP_KEY"

# Step 2: Securely copy them to localhost
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST:$REMOTE_TMP_CERT" "$LOCAL_CERT"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST:$REMOTE_TMP_KEY" "/tmp/privkey.pem"

# Step 3: Move private key with correct permissions (needs sudo)
sudo mv /tmp/privkey.pem "$LOCAL_KEY"
sudo chmod 600 "$LOCAL_KEY"

# Step 4: Clean up temporary files on remote server
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "sudo rm -f $REMOTE_TMP_CERT $REMOTE_TMP_KEY"

# Reloading apache service
sudo systemctl reload httpd.service
