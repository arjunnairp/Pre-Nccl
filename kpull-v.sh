#This script will:

#sriov
##Group worker nodes based on continuous IP addresses and print each group with a serial number.
##Prompt the user to select a group.
##Retrieve and display the number of GPUs, server model, and check if the allocatable value for "rdma/hca_shared_devices_c" is 500 for each server in the selected group.

#!/bin/bash

# Get all worker nodes and their IP addresses
worker_nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')

# Sort nodes by IP address
sorted_nodes=$(echo "$worker_nodes" | sort -k2)

# Function to check if two IPs are continuous
is_continuous() {
  local ip1=$1
  local ip2=$2
  local ip1_last_octet=$(echo $ip1 | awk -F. '{print $4}')
  local ip2_last_octet=$(echo $ip2 | awk -F. '{print $4}')
  if (( ip2_last_octet == ip1_last_octet + 1 )); then
    return 0
  else
    return 1
  fi
}

# Group nodes based on continuous IPs and assign serial numbers
current_group=""
previous_ip=""
serial_number=1
groups=()
echo -e "\e[32mWorker nodes grouped by continuous IPs:\e[0m"
while read -r node ip; do
  if [ -z "$previous_ip" ]; then
    current_group="$node"
  else
    if is_continuous "$previous_ip" "$ip"; then
      current_group="$current_group $node"
    else
      groups+=("Group $serial_number: $current_group")
      echo -e "\e[32mGroup $serial_number:\e[0m \e[1m$current_group\e[0m"
      serial_number=$((serial_number + 1))
      current_group="$node"
    fi
  fi
  previous_ip="$ip"
done <<< "$sorted_nodes"

# Print the last group
if [ -n "$current_group" ]; then
  groups+=("Group $serial_number: $current_group")
  echo -e "\e[32mGroup $serial_number:\e[0m \e[1m$current_group\e[0m"
fi

# Prompt user to select a group
read -p "Enter the group number to view details: " group_number

# Retrieve and display the number of GPUs, server model, and check allocatable values for each server in the selected group
selected_group=$(echo "${groups[$((group_number-1))]}" | awk '{for (i=3; i<=NF; i++) print $i}')

echo -e "\e[32mDetails for Group $group_number:\e[0m"
for node in $selected_group; do
  gpus=$(kubectl get node $node -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')
  model=$(kubectl get node $node -o jsonpath='{.metadata.labels.kubernetes\.io/hostname}')
  rdma=$(kubectl get node $node -o jsonpath='{.status.allocatable.rdma/hca_shared_devices_c}')

  echo -e "\e[1m$node\e[0m - GPUs: $gpus, Model: $model"

  if [[ "$rdma" == "500" ]]; then
    echo -e "Allocatable rdma/hca_shared_devices_c is 500 for $node \e[1m\e[32m\u2713\e[0m"
  else
    echo -e "\e[31mAllocatable rdma/hca_shared_devices_c is not 500 for $node \e[1m\e[31m\u2717\e[0m"
  fi
done
