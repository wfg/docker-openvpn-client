#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

iptables --insert OUTPUT \
    ! --out-interface tun0 \
    --match addrtype ! --dst-type LOCAL \
    ! --destination "$(ip -4 -oneline addr show dev eth0 | awk 'NR == 1 { print $4 }')" \
    --jump REJECT

# Create static routes for any ALLOWED_SUBNETS and punch holes in the firewall
# (ALLOWED_SUBNETS is passed as $1 from entry.sh)
default_gateway=$(ip -4 route | awk '$1 == "default" { print $3 }')
for subnet in ${1//,/ }; do
    ip route add "$subnet" via "$default_gateway"
    iptables --insert OUTPUT --destination "$subnet" --jump ACCEPT
done

# Punch holes in the firewall for the OpenVPN server addresses
# $config is set by OpenVPN:
#   "Name of first --config file. Set on program initiation and reset on SIGHUP."
global_port=$(awk '$1 == "port" { print $2 }' "${config:?"config file not found by kill switch"}")
global_protocol=$(awk '$1 == "proto" { print $2 }' "${config:?"config file not found by kill switch"}")
remotes=$(awk '$1 == "remote" { print $2, $3, $4 }' "${config:?"config file not found by kill switch"}")
ip_regex='^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$'
while IFS= read -r line; do
    # Read a comment-stripped version of the line
    # Fixes #84
    IFS=" " read -ra remote <<< "${line%%\#*}"
    address=${remote[0]}
    port=${remote[1]:-${global_port:-1194}}
    protocol=${remote[2]:-${global_protocol:-udp}}

    if [[ $address =~ $ip_regex ]]; then
        iptables --insert OUTPUT --destination "$address" --protocol "$protocol" --destination-port "$port" --jump ACCEPT
    else
        for ip in $(dig -4 +short "$address"); do
            iptables --insert OUTPUT --destination "$ip" --protocol "$protocol" --destination-port "$port" --jump ACCEPT
            echo "$ip $address" >> /etc/hosts
        done
    fi
done <<< "$remotes"
