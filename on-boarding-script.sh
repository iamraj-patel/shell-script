#!/bin/bash

# Update and upgrade system
sudo apt update && sudo apt upgrade -y

# Remove unnecessary packages
sudo apt autoremove -y

# Installing Rsyslog
sudo apt install rsyslog -y

# Create sudoers file for user 'raj'
echo "raj ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/raj

# Remove the machine-id file and create a symbolic link
sudo rm /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id

# Create ssh-keygen service
cat <<EOF | sudo tee /etc/systemd/system/ssh-keygen.service
[Unit]
Description=Generate SSH host keys on first boot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
EOF

# Enable and start ssh-keygen service
sudo systemctl enable ssh-keygen.service
sudo systemctl start ssh-keygen.service

# Remove SSH host key files
sudo rm /etc/ssh/ssh_host_*

# Truncate machine-id file
sudo truncate -s 0 /etc/machine-id

echo "alias c='clear'" | sudo tee -a /etc/bash.bashrc
echo "alias cls='c'" | sudo tee -a /etc/bash.bashrc

echo "alias c='clear'" | sudo tee -a /etc/profile
echo "alias cls='c'" | sudo tee -a /etc/profile

