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

PROXY_CONFIG_FILE=config/http-proxy.conf

ADDR_ETH0=$(ip address show "${TAP:-eth0}" | grep 'inet ' | awk '{split($2, inet, "/"); print inet[1]}')
ADDR_TUN0=$(ip address show tun0 | grep 'inet ' | awk '{split($2, inet, "/"); print inet[1]}')
sed -i \
    -e "/Listen/c Listen $ADDR_ETH0" \
    -e "/Bind/c Bind $ADDR_TUN0" \
    $PROXY_CONFIG_FILE

if [[ $HTTP_PROXY_USERNAME && $HTTP_PROXY_PASSWORD ]]; then
    log_msg 'info: starting http proxy with credentials'
    printf 'BasicAuth %s %s\n' "$HTTP_PROXY_USERNAME" "$HTTP_PROXY_PASSWORD" >> $PROXY_CONFIG_FILE
elif [[ -f "/run/secrets/$HTTP_PROXY_USERNAME_SECRET" && -f "/run/secrets/$HTTP_PROXY_PASSWORD_SECRET" ]]; then
    log_msg 'info: starting http proxy with credentials'
    printf 'BasicAuth %s %s\n' \
        "$(cat /run/secrets/"$HTTP_PROXY_USERNAME_SECRET")" \
        "$(cat /run/secrets/"$HTTP_PROXY_PASSWORD_SECRET")" >> $PROXY_CONFIG_FILE
else
    log_msg 'info: starting http proxy without credentials'
fi

exec tinyproxy -d -c $PROXY_CONFIG_FILE

# Never executed
exit $?
