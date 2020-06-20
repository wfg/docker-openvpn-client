#!/bin/sh

cleanup() {
    # When you run `docker stop` or any equivalent, a SIGTERM signal is sent to PID 1.
    # A process running as PID 1 inside a container is treated specially by Linux:
    # it ignores any signal with the default action. As a result, the process will
    # not terminate on SIGINT or SIGTERM unless it is coded to do so. Because of this,
    # I've defined behavior for when SIGINT and SIGTERM is received.
    if [ $healthcheck_child ]; then
        echo "Stopping healthcheck script..."
        kill -TERM $healthcheck_child
    fi

    if [ $openvpn_child ]; then
        echo "Stopping OpenVPN..."
        kill -TERM $openvpn_child
    fi

    sleep 1
    rm $config_file_modified
    echo "Exiting."
    exit 0
}

# Capture the filename of the first .conf file to use as the OpenVPN config.
config_file_original=$(ls -1 /data/vpn/*.conf 2> /dev/null | head -1)
if [ -z $config_file_original ]; then
    >&2 echo "ERROR: No configuration file found. Please check your mount and file permissions. Exiting."
    exit 1
fi

if ! $(echo $VPN_LOG_LEVEL | grep -Eq '^([1-9]|1[0-1])$'); then
    echo "WARNING: Invalid log level $VPN_LOG_LEVEL. Setting to default."
    vpn_log_level=3
else
    vpn_log_level=$VPN_LOG_LEVEL
fi

echo "
---- Running with the following variables ----
Kill switch: ${KILL_SWITCH:-off}
Tinyproxy: ${TINYPROXY:-off}
Shadowsocks: ${SHADOWSOCKS:-off}
Whitelisting subnets: ${SUBNETS:-none}
Using configuration file: $config_file_original
Using OpenVPN log level: $vpn_log_level
"

# Create a new configuration file to modify so the original is left untouched.
config_file_modified=${config_file_original}.modified

echo "Creating $config_file_modified and making required changes to that file."
cp $config_file_original $config_file_modified

# These configuration file changes are required by Alpine.
sed -i \
    -e '/up /c up \/etc\/openvpn\/up.sh' \
    -e '/down /c down \/etc\/openvpn\/down.sh' \
    -e 's/^proto udp$/proto udp4/' \
    -e 's/^proto tcp$/proto tcp4/' \
    $config_file_modified

if ! grep -q 'pull-filter ignore "route-ipv6"' $config_file_modified; then
    printf '\npull-filter ignore "route-ipv6"' >> $config_file_modified
fi

if ! grep -q 'pull-filter ignore "ifconfig-ipv6"' $config_file_modified; then
    printf '\npull-filter ignore "ifconfig-ipv6"' >> $config_file_modified
fi

echo -e "Changes made.\n"

trap cleanup INT TERM

if [ $KILL_SWITCH = "on" ]; then 
    local_subnet=$(ip r | grep -v 'default via' | grep eth0 | tail -n 1 | cut -d " " -f 1)
    default_gateway=$(ip r | grep 'default via' | cut -d " " -f 3)

    echo "Creating VPN kill switch and local routes."

    echo "Allowing established and related connections..."
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT

    echo "Allowing loopback connections..."
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    echo "Allowing Docker network connections..."
    iptables -A INPUT -s $local_subnet -j ACCEPT
    iptables -A OUTPUT -d $local_subnet -j ACCEPT

    echo "Allowing specified subnets..."
    # for every specified subnet...
    for subnet in ${SUBNETS//,/ }; do
        # create a route to it and...
        ip route add $subnet via $default_gateway dev eth0
        # allow connections
        iptables -A INPUT -s $subnet -j ACCEPT
        iptables -A OUTPUT -d $subnet -j ACCEPT
    done

    echo "Allowing remote servers in configuration file..."
    remote_port=$(grep "port " $config_file_modified | cut -d " " -f 2)
    remote_proto=$(grep "proto " $config_file_modified | cut -d " " -f 2 | cut -c1-3)
    remotes=$(grep "remote " $config_file_modified | cut -d " " -f 2-4)

    echo "  Using:"
    echo "$remotes" | while IFS= read line; do
        domain=$(echo "$line" | cut -d " " -f 1)
        port=$(echo "$line" | cut -d " " -f 2)
        proto=$(echo "$line" | cut -d " " -f 3 | cut -c1-3)
        for ip in $(dig -4 +short $domain); do
            echo "    $domain (IP:$ip PORT:$port)"
            iptables -A OUTPUT -o eth0 -d $ip -p ${proto:-$remote_proto} --dport ${port:-$remote_port} -j ACCEPT
        done
    done

    echo "Allowing connections over VPN interface..."
    iptables -A INPUT -i tun0 -j ACCEPT
    iptables -A OUTPUT -o tun0 -j ACCEPT

    echo "Allowing connections over VPN interface to forwarded ports..."
    if [ ! -z $FORWARDED_PORTS ]; then
        for port in ${FORWARDED_PORTS//,/ }; do
            if $(echo $port | grep -Eq '^[0-9]+$') && [ $port -ge 1024 ] && [ $port -le 65535 ]; then
                iptables -A INPUT -i tun0 -p tcp --dport $port -j ACCEPT
                iptables -A INPUT -i tun0 -p udp --dport $port -j ACCEPT
            else
                echo "WARNING: $port not a valid port. Ignoring."
            fi
        done
    fi

    echo "Preventing anything else..."
    iptables -P INPUT DROP
    iptables -P OUTPUT DROP
    iptables -P FORWARD DROP

    echo -e "iptables rules created and routes configured.\n"
else
    echo -e "WARNING: VPN kill switch is disabled. Traffic will be allowed outside of the tunnel if the connection is lost.\n"
fi

if [ "$SHADOWSOCKS" = "on" ]; then
    echo -e "Running Shadowsocks.\n"
    sed -i \
        -e "/server_port/c\    \"server_port\": ${SHADOWSOCKS_PORT:-8388}," \
        -e "/password/c\    \"password\": \"${SHADOWSOCKS_PASS:-password}\"," \
        /data/shadowsocks.conf
    /data/scripts/shadowsocks-wrapper.sh &
fi

if [ "$TINYPROXY" = "on" ]; then
    echo -e "Running Tinyproxy.\n"
    sed -i \
        -e "/Port/c Port ${TINYPROXY_PORT:-8888}" \
        /data/tinyproxy.conf

    if [ $TINYPROXY_USER ]; then
        if [ $TINYPROXY_PASS ]; then
            echo -e "\nBasicAuth $TINYPROXY_USER $TINYPROXY_PASS" >> /data/tinyproxy.conf
        else
            echo "WARNING: Tinyproxy username supplied without password. Starting without credentials."
        fi
    fi
    /data/scripts/tinyproxy-wrapper.sh &
fi

# /data/scripts/healthcheck.sh &
# healthcheck_child=$!

echo -e "Running OpenVPN client.\n"

openvpn --auth-nocache --cd /data/vpn --verb $vpn_log_level --config $config_file_modified &
openvpn_child=$!

wait $openvpn_child
