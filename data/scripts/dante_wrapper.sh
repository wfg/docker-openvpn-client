#!/bin/sh

echo -e "Running Dante SOCKS proxy server.\n"

until ping -c 3 1.1.1.1 > /dev/null 2>&1; do
    sleep 1
done

sockd -f /data/sockd.conf