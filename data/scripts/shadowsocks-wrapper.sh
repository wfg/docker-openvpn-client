#!/bin/sh

until ping -c 3 1.1.1.1 > /dev/null 2>&1; do
    sleep 1
done

ss-server -c /data/shadowsocks.conf