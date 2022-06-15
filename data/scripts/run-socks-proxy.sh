#!/usr/bin/env bash

set -e

until ip link show tun0 2>&1 | grep -qv "does not exist"; do
    sleep 1
done

proxy_config_file=config/socks-proxy.conf

if [[ $SOCKS_LISTEN_ON ]]; then
    sed -i "/internal: /c internal: $SOCKS_LISTEN_ON port = 1080" $proxy_config_file
fi
if [[ $SOCKS_PROXY_USERNAME && $SOCKS_PROXY_PASSWORD ]]; then
    printf 'info: starting socks proxy with credentials\n'
    useradd "$SOCKS_PROXY_USERNAME" -s /bin/false -M -p "$(mkpasswd "$SOCKS_PROXY_PASSWORD")"
    sed -i "/method: /c method: username" $proxy_config_file
elif [[ -f "/run/secrets/$SOCKS_PROXY_USERNAME_SECRET" && -f "/run/secrets/$SOCKS_PROXY_PASSWORD_SECRET" ]]; then
    printf 'info: starting socks proxy with credentials\n'
    useradd "$(cat /run/secrets/"$SOCKS_PROXY_USERNAME_SECRET")" -s /bin/false -M -p "$(mkpasswd "$(cat /run/secrets/"$SOCKS_PROXY_PASSWORD_SECRET")")"
    sed -i "/method: /c method: username" $proxy_config_file
else
    printf 'info: starting socks proxy without credentials\n'
fi

exec sockd -f $proxy_config_file
