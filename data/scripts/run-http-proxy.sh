#!/usr/bin/env bash

set -e

until ip link show tun0 2>&1 | grep -qv "does not exist"; do
    sleep 1
done

proxy_config_file=config/http-proxy.conf

addr_eth0=$(ip address show eth0 | grep 'inet ' | awk '{split($2, inet, "/"); print inet[1]}')
addr_tun0=$(ip address show tun0 | grep 'inet ' | awk '{split($2, inet, "/"); print inet[1]}')
sed -i \
    -e "/Listen/c Listen $addr_eth0" \
    -e "/Bind/c Bind $addr_tun0" \
    $proxy_config_file

if [[ $HTTP_PROXY_USERNAME && $HTTP_PROXY_PASSWORD ]]; then
    echo 'info: starting http proxy with credentials'
    printf 'BasicAuth %s %s\n' "$HTTP_PROXY_USERNAME" "$HTTP_PROXY_PASSWORD" >> $proxy_config_file
elif [[ -f "/run/secrets/$HTTP_PROXY_USERNAME_SECRET" && -f "/run/secrets/$HTTP_PROXY_PASSWORD_SECRET" ]]; then
    echo 'info: starting http proxy with credentials'
    printf 'BasicAuth %s %s\n' \
        "$(cat /run/secrets/"$HTTP_PROXY_USERNAME_SECRET")" \
        "$(cat /run/secrets/"$HTTP_PROXY_PASSWORD_SECRET")" >> $proxy_config_file
else
    echo 'info: starting http proxy without credentials'
fi

exec tinyproxy -d -c $proxy_config_file
