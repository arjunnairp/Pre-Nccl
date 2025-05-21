#!/bin/bash
#sriov

if [[ "$1" == "-info" ]]; then
    # Run the other shell script
    ./kpull-v.sh
    # Exit after executing the -info part
    exit 0
else
    echo "Usage: $0 -info"
fi

# Read configuration file
config_file="sconfig.para"
server_ips=()
nics=()
modules=()

while IFS= read -r line; do
  if [[ $line == \#* ]]; then
    continue
  elif [[ $line =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    server_ips+=("$line")
  elif [[ $line =~ ^(eth[0-9]+|enp[0-9]+s[0-9]+np[0-9]+)$ ]]; then
    nics+=("$line")
  elif [[ $line =~ ^[a-zA-Z0-9_-]+$ ]]; then
    modules+=("$line")
  fi
done < "$config_file"

all_servers_set=true

# Function to check NIC status, bring them up if down, set MTU if not 9000, check/load module status, and check/set IP forwarding
check_and_fix_nics_modules_and_ip_forwarding() {
  local server_ip=$1
  echo "Checking NICs, modules, and IP forwarding on server $server_ip"
  
  all_set=true
  
  for nic in "${nics[@]}"; do
    operstate=$(ssh $server_ip "cat /sys/class/net/$nic/operstate")
    mtu=$(ssh $server_ip "cat /sys/class/net/$nic/mtu")
    
    if [ "$operstate" == "up" ] && [ "$mtu" -eq 9000 ]; then
      echo -e "\e[32m$nic is up and has MTU 9000\e[0m"
    else
      echo -e "\e[31m$nic is not up or does not have MTU 9000\e[0m"
      ssh $server_ip "sudo ip link set $nic up"
      ssh $server_ip "sudo ip link set $nic mtu 9000"
      operstate=$(ssh $server_ip "cat /sys/class/net/$nic/operstate")
      mtu=$(ssh $server_ip "cat /sys/class/net/$nic/mtu")
      if [ "$operstate" == "up" ] && [ "$mtu" -eq 9000 ]; then
        echo -e "\e[32m$nic is now up and has MTU 9000\e[0m"
      else
        echo -e "\e[31m$nic failed to be set up or MTU 9000\e[0m"
        all_set=false
      fi
    fi
  done

  for module in "${modules[@]}"; do
    if ssh $server_ip "lsmod | grep -q $module"; then
      echo -e "\e[32mModule $module is loaded\e[0m"
    else
      echo -e "\e[31mModule $module is not loaded\e[0m"
      ssh $server_ip "sudo modprobe $module"
      if ssh $server_ip "lsmod | grep -q $module"; then
        echo -e "\e[32mModule $module is now loaded\e[0m"
      else
        echo -e "\e[31mFailed to load module $module\e[0m"
        all_set=false
      fi
    fi
  done

  ip_forward=$(ssh $server_ip "cat /proc/sys/net/ipv4/ip_forward")
  if [ "$ip_forward" -eq 1 ]; then
    echo -e "\e[32mIP forwarding is set\e[0m"
  else
    echo -e "\e[31mIP forwarding is not set\e[0m"
    ssh $server_ip "sudo sysctl -w net.ipv4.ip_forward=1"
    ip_forward=$(ssh $server_ip "cat /proc/sys/net/ipv4/ip_forward")
    if [ "$ip_forward" -eq 1 ]; then
      echo -e "\e[32mIP forwarding is now set\e[0m"
    else
      echo -e "\e[31mFailed to set IP forwarding\e[0m"
      all_set=false
    fi
  fi

  if [ "$all_set" = true ]; then
    echo -e "\e[32mAll checks passed for server \e[1m$server_ip\e[0m\e[32m\e[0m"
  else
    echo -e "\e[31mSome checks failed for server \e[1m$server_ip\e[0m\e[31m\e[0m"
    all_servers_set=false
  fi
}

# Loop through the IP range and check NICs, modules, and IP forwarding
for server_ip in "${server_ips[@]}"; do
  check_and_fix_nics_modules_and_ip_forwarding $server_ip
done

# Print final status
if [ "$all_servers_set" = true ]; then
  echo -e "\e[1m\e[32mCompletely set to go.....\e[0m"
else
  echo -e "\e[1m\e[31mSome checks failed on one or more servers\e[0m"
fi
