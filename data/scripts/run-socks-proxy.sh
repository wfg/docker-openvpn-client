#!/usr/bin/env bash

set -e

BASENAME=$(basename "$0")
log_msg() {
   echo -e "$(date +'%F %T')" ["$BASENAME"] "$@"
}

log_msg "Waiting for tun0 to become available ..."
until ip link show tun0 2>&1 | grep -qv "does not exist"; do
    sleep 0.5
done
log_msg "tun0 ready."

PROXY_CONFIG_FILE=config/socks-proxy.conf

if [[ $SOCKS_LISTEN_ON ]]; then
    sed -i "/internal: /c internal: $SOCKS_LISTEN_ON port = 1080" $PROXY_CONFIG_FILE
fi
if [[ $SOCKS_PROXY_USERNAME && $SOCKS_PROXY_PASSWORD ]]; then
    log_msg 'info: starting socks proxy with credentials'
    useradd "$SOCKS_PROXY_USERNAME" -s /bin/false -M -p "$(mkpasswd "$SOCKS_PROXY_PASSWORD")"
    sed -i "/method: /c method: username" $PROXY_CONFIG_FILE
elif [[ -f "/run/secrets/$SOCKS_PROXY_USERNAME_SECRET" && -f "/run/secrets/$SOCKS_PROXY_PASSWORD_SECRET" ]]; then
    log_msg 'info: starting socks proxy with credentials'
    useradd "$(cat /run/secrets/"$SOCKS_PROXY_USERNAME_SECRET")" -s /bin/false -M -p "$(mkpasswd "$(cat /run/secrets/"$SOCKS_PROXY_PASSWORD_SECRET")")"
    sed -i "/method: /c method: username" $PROXY_CONFIG_FILE
else
    log_msg 'info: starting socks proxy without credentials'
fi

exec sockd -f $PROXY_CONFIG_FILE

# Never executed
exit $?
