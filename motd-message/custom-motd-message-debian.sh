# Please run this sudo nano /etc/update-motd.d/99-custom-motd

# Then paste

#!/bin/bash
# A beautiful and clever MOTD for Raj Patel's Debian 13 server.
# This script uses ANSI escape codes for color and formatting.

# Define color variables for easier use
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# The width of the box for the welcome message
BOX_WIDTH=60

# --- MOTD Header ---
echo -e "${CYAN}------------------------------------------------------------${NC}"
echo -e "${CYAN}|${NC}${WHITE}                                                            ${NC}${CYAN}|${NC}"
echo -e "${CYAN}|${NC}${WHITE}  ${PURPLE}Welcome back to the command line, Raj Patel.${NC}          ${WHITE}   ${NC}${CYAN}|${NC}"
echo -e "${CYAN}|${NC}${WHITE}  ${GREEN}The server is ready for your brilliance.${NC}               ${WHITE}   ${NC}${CYAN}|${NC}"
echo -e "${CYAN}|${NC}${WHITE}                                                            ${NC}${CYAN}|${NC}"
echo -e "${CYAN}------------------------------------------------------------${NC}"
echo ""

# --- System Information Section ---
echo -e "${YELLOW}System Information:${NC}"

# Hostname and OS
HOSTNAME=$(hostnamectl | grep "Static hostname" | awk '{print $3}')
OS_INFO=$(hostnamectl | grep "Operating System" | awk -F': ' '{print $2}')
echo -e "  ${GREEN}Hostname:${NC}         $HOSTNAME"
echo -e "  ${GREEN}OS:${NC}               $OS_INFO"

# Kernel
KERNEL_VERSION=$(uname -r)
echo -e "  ${GREEN}Kernel Version:${NC}   $KERNEL_VERSION"

# Uptime
UPTIME=$(uptime -p)
echo -e "  ${GREEN}Uptime:${NC}           $UPTIME"

# IP Address
IP_ADDRESS=$(hostname -I | awk '{print $1}')
echo -e "  ${GREEN}IP Address:${NC}       $IP_ADDRESS"

# Disk Usage
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5" used"}')
echo -e "  ${GREEN}Disk Usage:${NC}       $DISK_USAGE"

# Memory Usage
MEM_USAGE=$(free -h | grep "Mem:" | awk '{print $3"/"$2}')
echo -e "  ${GREEN}Memory Usage:${NC}     $MEM_USAGE"
echo ""

# --- Footer ---
echo -e "${CYAN}------------------------------------------------------------${NC}"
echo -e "${YELLOW}  Use 'man' for help, 'sudo' for power, and 'exit' to leave.${NC}"
echo -e "${CYAN}------------------------------------------------------------${NC}"

# Paste above infomation but not the below informaiion
# -------------------------------------------------------------------------------------------------------------------------------------------------
# Then make executable /etc/update-motd.d/99-custom-motd
