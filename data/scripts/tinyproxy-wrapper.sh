#!/bin/sh

until ping -c 3 1.1.1.1 > /dev/null 2>&1; do
    sleep 1
done

# This part is in the wrapper script because addr_tun requires the VPN connection
# to be established.
addr_tun=$(ip a show dev tun0 | grep inet | cut -d " " -f 6 | cut -d "/" -f 1)
sed -i \
    -e "/Bind/c Bind $addr_tun" \
    /data/tinyproxy.conf

tinyproxy -d -c /data/tinyproxy.conf