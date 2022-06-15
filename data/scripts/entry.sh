#!/usr/bin/env bash

set -e


is_enabled() {
    [[ ${1,,} =~ ^(true|t|yes|y|1|on|enable|enabled)$ ]]
}

mkdir -p /data/{config,scripts,vpn}

echo "
--- Running with the following variables ---"

if [[ $VPN_CONFIG_FILE ]]; then
    echo "VPN configuration file: $VPN_CONFIG_FILE"
fi
if [[ $VPN_CONFIG_PATTERN ]]; then
    echo "VPN configuration file name pattern: $VPN_CONFIG_PATTERN"
fi

echo "Use default resolv.conf: ${USE_VPN_DNS:-off}
Allowing subnets: ${SUBNETS:-none}
Kill switch: $KILL_SWITCH
Using OpenVPN log level: $VPN_LOG_LEVEL"

if is_enabled "$HTTP_PROXY"; then
    echo "HTTP proxy: $HTTP_PROXY"
    if is_enabled "$HTTP_PROXY_USERNAME"; then
        echo "HTTP proxy username: $HTTP_PROXY_USERNAME"
    elif is_enabled "$HTTP_PROXY_USERNAME_SECRET"; then
        echo "HTTP proxy username secret: $HTTP_PROXY_USERNAME_SECRET"
    fi
fi
if is_enabled "$SOCKS_PROXY"; then
    echo "SOCKS proxy: $SOCKS_PROXY"
    if [[ $SOCKS_LISTEN_ON ]]; then
        echo "Listening on: $SOCKS_LISTEN_ON"
    fi
    if is_enabled "$SOCKS_PROXY_USERNAME"; then
        echo "SOCKS proxy username: $SOCKS_PROXY_USERNAME"
    elif is_enabled "$SOCKS_PROXY_USERNAME_SECRET"; then
        echo "SOCKS proxy username secret: $SOCKS_PROXY_USERNAME_SECRET"
    fi
fi

echo "---
"

if [[ $VPN_CONFIG_FILE ]]; then
    original_config_file=vpn/$VPN_CONFIG_FILE
elif [[ $VPN_CONFIG_PATTERN ]]; then
    original_config_file=$(find vpn -name "$VPN_CONFIG_PATTERN" 2> /dev/null | sort | shuf -n 1)
else
    original_config_file=$(find vpn -name '*.conf' -o -name '*.ovpn' 2> /dev/null | sort | shuf -n 1)
fi

if [[ -z $original_config_file ]]; then
    >&2 echo 'erro: no vpn configuration file found'
    exit 1
fi

echo "info: original configuration file: $original_config_file"

# Create a new configuration file to modify so the original is left untouched.
modified_config_file=vpn/openvpn.$(tr -dc A-Za-z0-9 </dev/urandom | head -c8).conf

echo "info: modified configuration file: $modified_config_file"
grep -Ev '(^up\s|^down\s)' "$original_config_file" > "$modified_config_file"

# Remove carriage returns (\r) from the config file
sed -i 's/\r$//g' "$modified_config_file"


default_gateway=$(ip -4 route | grep 'default via' | awk '{print $3}')
if is_enabled "$KILL_SWITCH" ; then
    echo "info: kill switch is on"

    nftables_config_file=config/nftables.conf

    local_subnet=$(ip -4 route | grep 'scope link' | awk '{print $1}')

    printf '%s\n' \
        '#!/usr/bin/nft' '' \
        'flush ruleset' '' \
        '# base ruleset' \
        'add table inet killswitch' '' \
        'add chain inet killswitch incoming { type filter hook input priority 0; policy drop; }' \
        'add rule inet killswitch incoming ct state established,related accept' \
        'add rule inet killswitch incoming iifname lo accept' '' \
        'add chain inet killswitch outgoing { type filter hook output priority 0; policy drop; }' \
        'add rule inet killswitch outgoing ct state established,related accept' \
        'add rule inet killswitch outgoing oifname lo accept' '' > $nftables_config_file

    printf '%s\n' \
        '# allow traffic to/from the Docker subnet' \
        "add rule inet killswitch incoming ip saddr $local_subnet accept" \
        "add rule inet killswitch outgoing ip daddr $local_subnet accept" '' >> $nftables_config_file

    if [[ $SUBNETS ]]; then
        printf '# allow traffic to/from the specified subnets\n' >> $nftables_config_file
        for subnet in ${SUBNETS//,/ }; do
            ip route add "$subnet" via "$default_gateway" dev eth0
            printf '%s\n' \
                "add rule inet killswitch incoming ip saddr $subnet accept" \
                "add rule inet killswitch outgoing ip daddr $subnet accept" '' >> $nftables_config_file
        done
    fi

    global_port=$(grep "^port " "$modified_config_file" | awk '{print $2}')
    global_protocol=$(grep "^proto " "$modified_config_file" | awk '{print $2}')  # {$2 = substr($2, 1, 3)} 2
    remotes=$(grep "^remote " "$modified_config_file" | awk '{print $2, $3, $4}')

    printf '# allow traffic to the VPN server(s)\n' >> $nftables_config_file
    ip_regex='^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$'
    while IFS= read -r line; do
        IFS=' ' read -ra remote <<< "$line"
        address=${remote[0]}
        port=${remote[1]:-${global_port:-1194}}
        protocol=${remote[2]:-${global_protocol:-udp}}

        if [[ $address =~ $ip_regex ]]; then
            printf '%s\n' \
                "add rule inet killswitch outgoing oifname eth0 ip daddr $address $protocol dport $port accept" >> $nftables_config_file
        else
            for ip in $(dig -4 +short "$address"); do
                printf '%s\n' \
                    "add rule inet killswitch outgoing oifname eth0 ip daddr $ip $protocol dport $port accept" >> $nftables_config_file
                printf "%s %s\n" "$ip" "$address" >> /etc/hosts
            done
        fi
    done <<< "$remotes"

    printf '%s\n' \
        '' '# allow traffic over the VPN interface' \
        "add rule inet killswitch incoming iifname tun0 accept" \
        "add rule inet killswitch outgoing oifname tun0 accept" >> $nftables_config_file

    nft -f $nftables_config_file
else
    echo "info: kill switch is off"
    for subnet in ${SUBNETS//,/ }; do
        ip route add "$subnet" via "$default_gateway" dev eth0
    done
fi

if is_enabled "$HTTP_PROXY" ; then
    scripts/run-http-proxy.sh &
fi

if is_enabled "$SOCKS_PROXY" ; then
    scripts/run-socks-proxy.sh &
fi

openvpn_args=(
    "--config" "$modified_config_file"
    "--auth-nocache"
    "--cd" "vpn"
    "--pull-filter" "ignore" "ifconfig-ipv6 "
    "--pull-filter" "ignore" "route-ipv6 "
    "--script-security" "2"
    "--up-restart"
    "--verb" "$VPN_LOG_LEVEL"
)

if is_enabled "$USE_VPN_DNS" ; then
    openvpn_args+=(
        "--up" "/etc/openvpn/up.sh"
        "--down" "/etc/openvpn/down.sh"
    )
fi

if [[ $VPN_AUTH_SECRET ]]; then
    openvpn_args+=("--auth-user-pass" "/run/secrets/$VPN_AUTH_SECRET")
fi

exec openvpn "${openvpn_args[@]}"
