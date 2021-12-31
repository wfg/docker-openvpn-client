#!/bin/bash

echo -e "Running Dante SOCKS proxy server.\n"

until ip link show tun0 2>&1 | grep -qv "does not exist"; do
    sleep 1
done

sockd -f /data/sockd.conf
