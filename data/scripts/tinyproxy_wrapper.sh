#!/bin/bash

echo -e "Running Tinyproxy HTTP proxy server.\n"

until ip link show tun0 2>&1 | grep -qv "does not exist"; do
    sleep 1
done

get_addr() {
   ip a show dev "$1" | grep inet | cut -d " " -f 6 | cut -d "/" -f 1
} 

addr_eth=${LISTEN_ON:-$(get_addr eth0)}
addr_tun=$(get_addr tun0)
sed -i \
    -e "/Listen/c Listen $addr_eth" \
    -e "/Bind/c Bind $addr_tun" \
    /data/tinyproxy.conf

tinyproxy -d -c /data/tinyproxy.conf
