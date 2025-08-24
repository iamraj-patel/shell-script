# Please run this sudo nano /etc/update-motd.d/99-custom-motd

# Then paste

#!/usr/bin/env bash
# A vibrant and informative MOTD for Raj Patel's server.
# Automatically detects your OS (Debian, Ubuntu, etc.)—no hard-coding.

# ANSI color codes
BOLD='\033[1m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# MOTD total width (characters)
WIDTH=70

# Pull the human-friendly name of your OS
OS_NAME=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"')

# Draw a colored horizontal line of ‘=’
print_line() {
  printf "${PURPLE}%${WIDTH}s${NC}\n" "" | tr ' ' '='
}

echo
print_line

# Centered welcome header
title1=" Welcome back, Raj Patel! "
printf "${PURPLE}|${NC} ${BOLD}${CYAN}%s${NC}%*s${PURPLE}|${NC}\n" \
  "$title1" $(( WIDTH - ${#title1} - 2 )) ""
title2="Your ${OS_NAME} server is primed for action."
printf "${PURPLE}|${NC} ${WHITE}%s${NC}%*s${PURPLE}|${NC}\n" \
  "$title2" $(( WIDTH - ${#title2} - 2 )) ""
print_line
echo

## System Information
echo -e "${YELLOW}System Information${NC}"
echo -e "  ${GREEN}Hostname:${NC}        $(hostname)"
echo -e "  ${GREEN}OS:${NC}              ${OS_NAME}"
echo -e "  ${GREEN}Kernel:${NC}          $(uname -r)"
echo -e "  ${GREEN}Uptime:${NC}          $(uptime -p)"
echo -e "  ${GREEN}Users logged in:${NC} $(who | wc -l)"
echo -e "  ${GREEN}Load average:${NC}    $(uptime | awk -F'load average: ' '{print $2}')"
echo

## Resource Usage
echo -e "${YELLOW}Resource Usage${NC}"
CPU_USAGE=$(top -bn1 | awk '/Cpu\(s\):/ {printf "%.1f%%", $2 + $4}')
MEM_USAGE=$(free -h | awk '/^Mem:/ {print $3 " of " $2}')
SWAP_USAGE=$(free -h | awk '/^Swap:/ {print $3 " of " $2}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5 " used"}')
PROCS=$(ps ax --no-heading | wc -l)

echo -e "  ${GREEN}CPU Usage:${NC}       ${CPU_USAGE}"
echo -e "  ${GREEN}Memory Usage:${NC}    ${MEM_USAGE}"
echo -e "  ${GREEN}Swap Usage:${NC}      ${SWAP_USAGE}"
echo -e "  ${GREEN}Disk / Usage:${NC}     ${DISK_USAGE}"
echo -e "  ${GREEN}Processes:${NC}       ${PROCS}"
echo

## Network Information
echo -e "${YELLOW}Network Information${NC}"
echo -e "  ${GREEN}IP Address:${NC}      $(hostname -I | awk '{print $1}')"
echo -e "  ${GREEN}Default Gateway:${NC} $(ip route | awk '/default/ {print $3}')"
echo

## Footer
print_line
echo -e "${CYAN}  Use '${YELLOW}man${CYAN}' for help, '${YELLOW}sudo${CYAN}' for power, and '${YELLOW}exit${CYAN}' to leave.${NC}"
print_line
echo

# Paste above infomation but not the below informaiion
# -------------------------------------------------------------------------------------------------------------------------------------------------
# Then make executable /etc/update-motd.d/99-custom-motd
