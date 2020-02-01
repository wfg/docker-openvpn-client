#!/bin/sh

################################################################################

config_file=$(ls -1 /data/vpn/*.conf 2>/dev/null | head -1)
if [ -z $config_file ]; then
    >&2 echo "[ERRO] No configuration file found. Please check your mount and file permissions. Exiting."
    exit 1
fi

LOG_LEVEL=${LOG_LEVEL:-3}
if ! $(echo $LOG_LEVEL | grep -Eq '^([1-9]|1[0-1])$'); then
    echo "[WARN] Invalid log level $LOG_LEVEL. Setting to default."
    LOG_LEVEL=3
fi

echo -e "\n---- Details ----"
echo "Whitelisting subnets: ${SUBNETS:-none}"
echo "Using configuration file: $config_file"
echo "Using OpenVPN log level: $LOG_LEVEL"

################################################################################

echo -e "\n---- OpenVPN and Tinyproxy ----"

echo "Making changes to the configuration file."
sed -i \
    -e '/up /c up \/etc\/openvpn\/up.sh' \
    -e '/down /c down \/etc\/openvpn\/down.sh' \
    -e 's/^proto udp$/proto udp4/' \
    -e 's/^proto tcp$/proto tcp4/' \
    $config_file

if ! grep -q 'pull-filter ignore "route-ipv6"' $config_file; then
    printf '\npull-filter ignore "route-ipv6"' >> $config_file
fi

if ! grep -q 'pull-filter ignore "ifconfig-ipv6"' $config_file; then
    printf '\npull-filter ignore "ifconfig-ipv6"' >> $config_file
fi

cp /data/vpn/* /etc/openvpn

echo "[INFO] Changes made and files moved into place."

################################################################################

echo -e "\n---- Network and Firewall ----"
local_subnet=$(ip r | grep -v 'default via' | grep eth0 | tail -n 1 | cut -d " " -f 1)
default_gateway=$(ip r | grep 'default via' | cut -d " " -f 3)

echo "Creating VPN kill switch and local routes."
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# allows established and related connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# allows loopback connections
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# allows Docker network connections
iptables -A INPUT -s $local_subnet -j ACCEPT
iptables -A OUTPUT -d $local_subnet -j ACCEPT

# for every specified subnet...
for subnet in ${SUBNETS//,/ }; do
    # create a route to it and...
    ip route add $subnet via $default_gateway dev eth0
    # allow connections
    iptables -A INPUT -s $subnet -j ACCEPT
    iptables -A OUTPUT -d $subnet -j ACCEPT
done

# allows OpenVPN connections only to addresses in configuration file
remote_port=$(grep "port " $config_file | cut -d " " -f 2)
remote_proto=$(grep "proto " $config_file | cut -d " " -f 2 | cut -c1-3)
remotes=$(grep "remote " $config_file | cut -d " " -f 2-4)

while IFS= read line; do
    domain=$(echo "$line" | cut -d " " -f 2)
    port=$(echo "$line" | cut -d " " -f 3)
    proto=$(echo "$line" | cut -d " " -f 4 | cut -c1-3)
    for ip in $(nslookup $domain localhost | tail -n +4 | grep -Eo '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' | sort | uniq); do
        iptables -A OUTPUT -o eth0 -d $ip -p ${proto:-$remote_proto} --dport ${port:-$remote_port} -j ACCEPT
    done
done <<< "$remotes"

# allow connections over VPN interface...
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A OUTPUT -o tun0 -j ACCEPT

# and over VPN interface to forwarded ports
if [ ! -z $FORWARDED_PORTS ]; then
    for port in ${FORWARDED_PORTS//,/ }; do
        if [ $port -lt 1024 ] || [ $port -gt 65535 ]; then
            echo "[WARN] $port not a valid port. Ignoring."
        fi
        iptables -A INPUT -i tun0 -p tcp --dport $port -j ACCEPT
        iptables -A INPUT -i tun0 -p udp --dport $port -j ACCEPT
    done
fi

echo "[INFO] iptables rules created and routes configured."

################################################################################

{
    if [ "$TINYPROXY" = "on" ]; then
        echo "[INFO] Running tinyproxy"
        # Wait for VPN connection to be established
        while ! ping -c 1 1.1.1.1 > /dev/null 2&>1; do
            sleep 1
        done

        addr_eth=$(hostname -i)
        addr_tun=$(ip a show dev tun0 | grep inet | cut -d " " -f 6 | cut -d "/" -f 1)
        TINYPROXY_PORT=${TINYPROXY_PORT:-8888}

        sed -i \
            -e "/Port/c Port $TINYPROXY_PORT" \
            -e "/Listen/c Listen $addr_eth" \
            -e "/Bind/c Bind $addr_tun" \
            /etc/tinyproxy/tinyproxy.conf

        if [ ! -z $TINYPROXY_USER ]; then
            if [ ! -z $TINYPROXY_PASS ]; then
                echo -e "\nBasicAuth $TINYPROXY_USER $TINYPROXY_PASS" >> /etc/tinyproxy/tinyproxy.conf
            else
                echo "[WARN] Tinyproxy username supplied without password. Starting without credentials."
            fi
        fi

        tinyproxy -c /etc/tinyproxy/tinyproxy.conf
    fi
} &

cd /etc/openvpn

openvpn --verb $LOG_LEVEL --config $config_file