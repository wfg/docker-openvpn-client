#!/bin/ash
# shellcheck shell=ash
# shellcheck disable=SC2169 # making up for lack of ash support

echo -e "Running Tinyproxy HTTP proxy server.\n"

until ip link show tun0 2>&1 | grep -qv "does not exist"; do
    sleep 1
done

function get_addr {
   echo $(ip a show dev $1 | grep inet | cut -d " " -f 6 | cut -d "/" -f 1)
} 

addr_eth=${LISTEN_ON:-$(get_addr eth0)}
addr_tun=$(get_addr tun0)
sed -i \
    -e "/Listen/c Listen $addr_eth" \
    -e "/Bind/c Bind $addr_tun" \
    /data/tinyproxy.conf

tinyproxy -d -c /data/tinyproxy.conf
