#!/bin/bash

# Update and upgrade system
sudo dnf update -y
sudo dnf upgrade -y

# Remove unnecessary packages
sudo dnf autoremove -y

# Install cloud-init
sudo dnf install cloud-init -y

# Enable cloud-init service
sudo systemctl enable cloud-init.service
sudo systemctl start cloud-init.service

# Add aliases globally
echo "alias c='clear'" | sudo tee -a /etc/bashrc
echo "alias cls='c'" | sudo tee -a /etc/bashrc

# Add aliases to profile to ensure global availability
echo "alias c='clear'" | sudo tee -a /etc/profile
echo "alias cls='c'" | sudo tee -a /etc/profile

# Truncate machine-id file
sudo truncate -s 0 /etc/machine-id

# Remove SSH host key files
sudo rm /etc/ssh/ssh_host_*

# Clean all DNF caches
sudo dnf clean all

sudo poweroff
