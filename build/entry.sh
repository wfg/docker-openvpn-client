#!/usr/bin/env bash

set -o errexit
set -o pipefail

cleanup() {
    kill TERM "$openvpn_pid"
    exit 0
}

is_enabled() {
    [[ ${1,,} =~ ^(true|t|yes|y|1|on|enable|enabled)$ ]]
}

# Either a specific file name or a pattern.
if [[ $CONFIG_FILE ]]; then
    config_file=$(find /config -name "$CONFIG_FILE" 2> /dev/null | sort | shuf -n 1)
else
    config_file=$(find /config -name '*.conf' -o -name '*.ovpn' 2> /dev/null | sort | shuf -n 1)
fi

if [[ -z $config_file ]]; then
    echo "no openvpn configuration file found" >&2
    exit 1
fi

echo "using openvpn configuration file: $config_file"


openvpn_args=(
    "--config" "$config_file"
    "--cd" "/"
)

if is_enabled "$KILL_SWITCH"; then
    openvpn_args+=("--route-up" "/usr/local/bin/killswitch.sh $ALLOWED_SUBNETS")
fi

# Docker secret that contains the credentials for accessing the VPN.
if [[ $AUTH_SECRET ]]; then
    openvpn_args+=("--auth-user-pass" "/run/secrets/$AUTH_SECRET")
elif [[ $AUTH_SECRET_FILE ]]; then

openvpn_args+=("--auth-user-pass" "$AUTH_SECRET_FILE")

fi

openvpn "${openvpn_args[@]}" &
openvpn_pid=$!

trap cleanup TERM

wait $openvpn_pid
