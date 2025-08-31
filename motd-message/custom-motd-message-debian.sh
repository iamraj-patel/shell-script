# Please run this sudo nano /etc/update-motd.d/99-custom-motd

# Then paste

#!/usr/bin/env bash
# A more dynamic and informative MOTD for Raj Patel's server.

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

# Function to draw a colored horizontal line of ‘=’
print_line() {
  printf "${PURPLE}%${WIDTH}s${NC}\n" "" | tr ' ' '='
}

# --- Header Section ---
echo
print_line

# Centered welcome header
title1=" Welcome back, Raj Patel! "
printf "${PURPLE}|${NC} ${BOLD}${CYAN}%s${NC}%*s${PURPLE}|${NC}\n" \
  "$title1" $(( WIDTH - ${#title1} - 2 )) ""
title2=" Your ${OS_NAME} server is primed for action. "
printf "${PURPLE}|${NC} ${WHITE}%s${NC}%*s${PURPLE}|${NC}\n" \
  "$title2" $(( WIDTH - ${#title2} - 2 )) ""

print_line
echo

# --- System Overview ---
echo -e "${BOLD}${YELLOW}System Overview${NC}"
echo -e "  ${GREEN}Hostname:${NC}        $(hostname)"
echo -e "  ${GREEN}OS:${NC}              ${OS_NAME}"
echo -e "  ${GREEN}Kernel:${NC}          $(uname -r)"
echo -e "  ${GREEN}Uptime:${NC}          $(uptime -p)"
echo -e "  ${GREEN}Users Logged In:${NC} $(who | wc -l)"
echo -e "  ${GREEN}Load Average:${NC}    $(uptime | awk -F'load average: ' '{print $2}')"
echo

# --- Resource Usage ---
echo -e "${BOLD}${YELLOW}Resource Usage${NC}"
CPU_USAGE=$(top -bn1 | awk '/Cpu\(s\):/ {printf "%.1f%%", $2 + $4}')
MEM_USAGE=$(free -h | awk '/^Mem:/ {print $3 " of " $2}')
SWAP_USAGE=$(free -h | awk '/^Swap:/ {print $3 " of " $2}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5 " used"}')
PROCS=$(ps ax --no-heading | wc -l)

echo -e "  ${GREEN}CPU Usage:${NC}       ${CPU_USAGE}"
echo -e "  ${GREEN}Memory Usage:${NC}    ${MEM_USAGE}"
echo -e "  ${GREEN}Swap Usage:${NC}      ${SWAP_USAGE}"
echo -e "  ${GREEN}Disk / Usage:${NC}    ${DISK_USAGE}"
echo -e "  ${GREEN}Processes:${NC}       ${PROCS}"
echo

# --- Network & Updates ---
echo -e "${BOLD}${YELLOW}Network & Updates${NC}"
IP_ADDRESS=$(hostname -I | awk '{print $1}')
GATEWAY=$(ip route | awk '/default/ {print $3}')
UPDATES=0

# Check for package updates (works for Debian/Ubuntu)
if command -v apt >/dev/null 2>&1; then
  UPDATES=$(apt list --upgradable 2>/dev/null | grep -c 'upgradable')
fi

echo -e "  ${GREEN}IP Address:${NC}      ${IP_ADDRESS}"
echo -e "  ${GREEN}Default Gateway:${NC} ${GATEWAY}"
echo -e "  ${GREEN}Package Updates:${NC} ${UPDATES} available. Run '${CYAN}sudo apt update${NC}${NC}'"
echo

# --- Weather Information ---
# This requires 'curl' and 'jq' to be installed.
# You can install them with 'sudo apt install curl jq'.
# It uses the 'wttr.in' service to get weather based on your IP.
echo -e "${BOLD}${YELLOW}Current Weather${NC}"
WEATHER_INFO=$(curl -s wttr.in?format="%c+%t+%w" | head -n 1)
if [ -n "$WEATHER_INFO" ]; then
  echo -e "  ${GREEN}Location:${NC}        ${WEATHER_INFO}"
else
  echo "  ${RED}Weather information unavailable.${NC}"
fi
echo

# --- Fun/Informative Footer ---
print_line

# A simple "Tip of the Day"
TIPS=(
"Use '${CYAN}tmux${NC}' or '${CYAN}screen${NC}' to keep your sessions alive."
"Press '${CYAN}Ctrl+R${NC}' in the terminal to search command history."
"Try '${CYAN}htop${NC}' for a better view of your system processes."
"The '${CYAN}du -sh *${NC}' command shows directory sizes in a human-readable format."
"Use '${CYAN}grep -r <text> .${NC}' to search for text in files recursively."
)
TIP_OF_THE_DAY=${TIPS[$(( RANDOM % ${#TIPS[@]} ))]}

echo -e "${BOLD}${CYAN}  Tip of the Day:${NC} ${TIP_OF_THE_DAY}"
echo -e "${CYAN}  Remember: Use '${YELLOW}man${CYAN}' for help, '${YELLOW}sudo${CYAN}' for power, and '${YELLOW}exit${CYAN}' to leave.${NC}"
print_line
echo

# Paste above infomation but not the below informaiion
# -------------------------------------------------------------------------------------------------------------------------------------------------
# Then make executable /etc/update-motd.d/99-custom-motd
