#!/bin/bash

# Detect the OS family
if [ -f /etc/debian_version ]; then
  # Debian-based system
  echo "Configuring Debian/Ubuntu-based system."

  # Update and upgrade system
  sudo apt update && sudo apt upgrade -y

  # Remove unnecessary packages
  sudo apt autoremove -y

  # Install Rsyslog
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

  # Add aliases globally and to user profiles
  echo "alias c='clear'" | sudo tee -a /etc/bash.bashrc
  echo "alias cls='c'" | sudo tee -a /etc/bash.bashrc

  echo "alias c='clear'" | sudo tee -a /etc/profile
  echo "alias cls='c'" | sudo tee -a /etc/profile

  echo "alias c='clear'" >> ~/.bashrc
  echo "alias cls='c'" >> ~/.bashrc

  sudo poweroff

elif [ -f /etc/redhat-release ]; then
  # RHEL-based system (AlmaLinux)
  echo "Configuring Fedora/RHEL-based system."

  # Update and upgrade system
  sudo dnf update -y && sudo dnf upgrade -y

  # Remove unnecessary packages
  sudo dnf autoremove -y

  # Install cloud-init
  sudo dnf install cloud-init -y

  # Enable cloud-init service
  sudo systemctl enable cloud-init.service
  sudo systemctl start cloud-init.service

  # Create sudoers file for user 'raj'
  echo "raj ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/raj
  sudo chmod 0440 /etc/sudoers.d/raj

  # Add aliases globally and to user profiles
  echo "alias c='clear'" | sudo tee -a /etc/bashrc
  echo "alias cls='c'" | sudo tee -a /etc/bashrc

  echo "alias c='clear'" | sudo tee -a /etc/profile
  echo "alias cls='c'" | sudo tee -a /etc/profile

  echo "alias c='clear'" >> ~/.bashrc
  echo "alias cls='c'" >> ~/.bashrc

  # Truncate machine-id file
  sudo truncate -s 0 /etc/machine-id

  # Remove SSH host key files
  sudo rm /etc/ssh/ssh_host_*

  # Clean all DNF caches
  sudo dnf clean all

  sudo poweroff
else
  echo "Unsupported OS family."
  exit 1
fi
