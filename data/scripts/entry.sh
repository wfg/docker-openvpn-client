#!/usr/bin/env bash

set -e

BASENAME=$(basename "$0")
log_msg() {
   echo -e "$(date +'%F %T')" ["$BASENAME"] "$@"
}

cleanup() {
   if [[ -n "$OPENVPN_CHILD" ]]; then
      log_msg "Asking openvpn to exit gracefully"
      kill SIGTERM $OPENVPN_CHILD > /dev/null 2>&1
      I=15
      while [[ $I -ge 0 ]] ; do
         kill -0 $OPENVPN_CHILD > /dev/null 2>&1
         if [[ $? -eq 1 ]] ; then
            break
         fi
         log_msg "Waiting on openvpn to end ... $I"
         sleep 1
         ((I--))
      done
   fi
}

is_enabled() {
   [[ ${1,,} =~ ^(true|t|yes|y|1|on|enable|enabled)$ ]]
}

dump_user_settings() {
   log_msg "User settings"
   log_msg "============="

   if [[ $VPN_CONFIG_FILE ]]; then
      log_msg "VPN configuration file: $VPN_CONFIG_FILE"
   fi
   if [[ $VPN_CONFIG_PATTERN ]]; then
      log_msg "VPN configuration file name pattern: $VPN_CONFIG_PATTERN"
   fi

   log_msg "Use default resolv.conf: ${USE_VPN_DNS:-off}"
   log_msg "Allowing subnets: ${SUBNETS:-none}"
   log_msg "Kill switch method: $KILL_SWITCH"
   log_msg "Connect retry (--connect-retry): ${RETRY:-5} ${MAX_RETRY:-60} second(s)"
   log_msg "Server poll timeout (--server-poll-timeout): ${SERVER_POLL:-120}"
   log_msg "Ping (--ping): ${PING:-15}"
   log_msg "Ping restart (--ping-restart): ${PING_RESTART:-120}"
   log_msg "Using OpenVPN log level: $VPN_LOG_LEVEL"
   if [[ -n "$TAP" ]] ; then
      log_msg "Container script 'eth0' remapped to '${TAP}'"
   else
      log_msg "Container script 'eth0' not remapped."
   fi
   if [[ -n "$USE_FAST_IO" ]] ; then
      log_msg "Fast IO enabled (--fast-io), a non-Windows, UDP-only switch"
   fi
   if [[ -n "$SNDBUF" ]] ; then
      log_msg "Send buffer (--sndbuf): ${SNDBUF}"
   fi
   if [[ -n "$RCVBUF" ]] ; then
      log_msg "Receive buffer (--sndbuf): ${RCVBUF}"
   fi

   if is_enabled "$HTTP_PROXY"; then
      log_msg "HTTP proxy: $HTTP_PROXY"
      if is_enabled "$HTTP_PROXY_USERNAME"; then
         log_msg "HTTP proxy username: $HTTP_PROXY_USERNAME"
      elif is_enabled "$HTTP_PROXY_USERNAME_SECRET"; then
         log_msg "HTTP proxy username secret: $HTTP_PROXY_USERNAME_SECRET"
      fi
   fi
   if is_enabled "$SOCKS_PROXY"; then
      log_msg "SOCKS proxy: $SOCKS_PROXY"
      if [[ $SOCKS_LISTEN_ON ]]; then
         log_msg "SOCKS istening on: $SOCKS_LISTEN_ON"
      fi
      if is_enabled "$SOCKS_PROXY_USERNAME"; then
         log_msg "SOCKS proxy username: $SOCKS_PROXY_USERNAME"
      elif is_enabled "$SOCKS_PROXY_USERNAME_SECRET"; then
         log_msg "SOCKS proxy username secret: $SOCKS_PROXY_USERNAME_SECRET"
      fi
   fi

   if [[ -n "$DEBUG_VPN_CONFIG_FILE" ]] ; then
      log_msg "Keeping modified .ovpn file with source .ovpn file"
   fi
}

gen_working_VPN_file() {
   if [[ $VPN_CONFIG_FILE ]]; then
      ORIGINAL_CONFIG_FILE=vpn/$VPN_CONFIG_FILE
   elif [[ $VPN_CONFIG_PATTERN ]]; then
      ORIGINAL_CONFIG_FILE=$(find vpn -name "$VPN_CONFIG_PATTERN" 2> /dev/null | sort | shuf -n 1)
   else
      ORIGINAL_CONFIG_FILE=$(find vpn -name '*.conf' -o -name '*.ovpn' 2> /dev/null | sort | shuf -n 1)
   fi

   if [[ ! -f $ORIGINAL_CONFIG_FILE ]]; then
      >&2 log_msg "erro: no vpn configuration file found"
      exit 1
   fi

   log_msg "info: original configuration file: $ORIGINAL_CONFIG_FILE"

   # Create a new configuration file to modify so the original is left
   # untouched.
   #
   # Use the passed in $DEBUG_VPN_CONFIG_FILE variable to determine whether
   # the modified file is ephemeral or not.
   MOD_DIR="/tmp"
   if [[ -n "$DEBUG_VPN_CONFIG_FILE" ]] ; then
      MOD_DIR="vpn"
   fi
   MODIFIED_CONFIG_FILE=$MOD_DIR/openvpn.$(tr -dc A-Za-z0-9 </dev/urandom | head -c8).conf

   log_msg "info: modified configuration file: $MODIFIED_CONFIG_FILE"
   grep -Ev '(^up\s|^down\s)' "$ORIGINAL_CONFIG_FILE" > "$MODIFIED_CONFIG_FILE"

   # Remove carriage returns (\r) from the config file
   sed -i 's/\r$//g' "$MODIFIED_CONFIG_FILE"
}

setup_kill_switch() {
   DEFAULT_GATEWAY=$(ip -4 route | grep 'default via' | awk '{print $3}')
   case "$KILL_SWITCH" in
      'iptables')
         log_msg "Configuring $KILL_SWITCH kill switch"

         iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
         iptables -A INPUT -i lo -j ACCEPT
         iptables -A OUTPUT -o lo -j ACCEPT

         LOCAL_SUBNET=$(ip -4 route | grep 'scope link' | awk '{print $1}')
         iptables -A INPUT -s "$LOCAL_SUBNET" -j ACCEPT
         iptables -A OUTPUT -d "$LOCAL_SUBNET" -j ACCEPT

         if [[ $SUBNETS ]]; then
            for SUBNET in ${SUBNETS//,/ }; do
               ip route add "$SUBNET" via "$DEFAULT_GATEWAY" dev "${TAP:-eth0}"
               iptables -A INPUT -s "$SUBNET" -j ACCEPT
               iptables -A OUTPUT -d "$SUBNET" -j ACCEPT
            done
         fi

         GLOBAL_PORT=$(grep "^port " "$MODIFIED_CONFIG_FILE" | awk '{print $2}')
         GLOBAL_PROTOCOL=$(grep "^proto " "$MODIFIED_CONFIG_FILE" | awk '{print $2}')  # {$2 = substr($2, 1, 3)} 2
         REMOTES=$(grep "^remote " "$MODIFIED_CONFIG_FILE" | awk '{print $2, $3, $4}')
         IP_REGEX='^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$'
         while IFS= read -r LINE; do
            IFS=' ' read -ra REMOTE <<< "$LINE"
            ADDRESS=${REMOTE[0]}
            PORT=${REMOTE[1]:-${GLOBAL_PORT:-1194}}
            PROTOCOL=${REMOTE[2]:-${GLOBAL_PROTOCOL:-udp}}

            if [[ $ADDRESS =~ $IP_REGEX ]]; then
               iptables -A OUTPUT -o "${TAP:-eth0}" -d "$ADDRESS" -p "$PROTOCOL" --dport "$PORT" -j ACCEPT
            else
               log_msg "dig lookup on $ADDRESS"
               for IP in $(dig -4 +timeout="${DIG_TIMEOUT:-5}" +tries=1 +short "$ADDRESS"); do
                  if echo "$IP" | grep -s '^[0-9]' > /dev/null 2>&1 ; then
                     iptables -A OUTPUT -o "${TAP:-eth0}" -d "$IP" -p "$PROTOCOL" --dport "$PORT" -j ACCEPT
                     printf "%s %s\n" "$IP" "$ADDRESS" >> /etc/hosts
                  else
                     log_msg "dig returned malformed IP ($IP).  Cannot recover. Bye."
                     exit 1
                  fi
               done
            fi
         done <<< "$REMOTES"
         iptables -A INPUT -i tun0 -j ACCEPT
         iptables -A OUTPUT -o tun0 -j ACCEPT
         iptables -P INPUT DROP
         iptables -P OUTPUT DROP
         iptables -P FORWARD DROP
         iptables-save > config/iptables.conf
         ;;
      'nftables')
         log_msg "Configuring $KILL_SWITCH kill switch"

         NFTABLES_CONFIG_FILE=config/nftables.conf

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
                'add rule inet killswitch outgoing oifname lo accept' '' > $NFTABLES_CONFIG_FILE

         LOCAL_SUBNET=$(ip -4 route | grep 'scope link' | awk '{print $1}')
         printf '%s\n' \
                '# allow traffic to/from the Docker subnet' \
                "add rule inet killswitch incoming ip saddr $LOCAL_SUBNET accept" \
                "add rule inet killswitch outgoing ip daddr $LOCAL_SUBNET accept" '' >> $NFTABLES_CONFIG_FILE

         if [[ $SUBNETS ]]; then
            printf '# allow traffic to/from the specified subnets\n' >> $NFTABLES_CONFIG_FILE
            for subnet in ${SUBNETS//,/ }; do
               ip route add "$subnet" via "$DEFAULT_GATEWAY" dev "${TAP:-eth0}"
               printf '%s\n' \
                      "add rule inet killswitch incoming ip saddr $subnet accept" \
                      "add rule inet killswitch outgoing ip daddr $subnet accept" '' >> $NFTABLES_CONFIG_FILE
            done
         fi

         GLOBAL_PORT=$(grep "^port " "$MODIFIED_CONFIG_FILE" | awk '{print $2}')
         GLOBAL_PROTOCOL=$(grep "^proto " "$MODIFIED_CONFIG_FILE" | awk '{print $2}')  # {$2 = substr($2, 1, 3)} 2
         REMOTES=$(grep "^remote " "$MODIFIED_CONFIG_FILE" | awk '{print $2, $3, $4}')

         printf '# allow traffic to the VPN server(s)\n' >> $NFTABLES_CONFIG_FILE
         IP_REGEX='^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$'
         while IFS= read -r LINE; do
            IFS=' ' read -ra REMOTE <<< "$LINE"
            ADDRESS=${REMOTE[0]}
            PORT=${REMOTE[1]:-${GLOBAL_PORT:-1194}}
            PROTOCOL=${REMOTE[2]:-${GLOBAL_PROTOCOL:-udp}}

            if [[ $ADDRESS =~ $IP_REGEX ]]; then
               printf '%s\n' \
                      "add rule inet killswitch outgoing oifname ${TAP:-eth0} ip daddr $ADDRESS $PROTOCOL dport $PORT accept" >> $NFTABLES_CONFIG_FILE
            else
               log_msg "dig lookup on $ADDRESS"
               for IP in $(dig -4 +timeout="${DIG_TIMEOUT:-5}" +tries=1 +short "$ADDRESS"); do
                  if echo "$IP" | grep -s '^[0-9]' > /dev/null 2>&1 ; then
                     printf '%s\n' \
                            "add rule inet killswitch outgoing oifname ${TAP:-eth0} ip daddr $IP $PROTOCOL dport $PORT accept" >> $NFTABLES_CONFIG_FILE
                     printf "%s %s\n" "$IP" "$ADDRESS" >> /etc/hosts
                  else
                     log_msg "dig returned malformed IP ($IP).  Cannot recover.  Bye."
                     exit 1
                  fi
               done
            fi
         done <<< "$REMOTES"

         printf '%s\n' \
                '' '# allow traffic over the VPN interface' \
                "add rule inet killswitch incoming iifname tun0 accept" \
                "add rule inet killswitch outgoing oifname tun0 accept" >> $NFTABLES_CONFIG_FILE

         nft -f $NFTABLES_CONFIG_FILE
         ;;
      *)
         log_msg "info: kill switch is off"
         for subnet in ${SUBNETS//,/ }; do
            ip route add "$subnet" via "$DEFAULT_GATEWAY" dev "${TAP:-eth0}"
         done
         ;;
   esac
}

####################### Main #######################
log_msg "Container start"

mkdir -p /data/{config,scripts,vpn}

# Dump our devices as it may help the end-user determine if they need to
# override our script's use of `eth0'
log_msg "Devices"
log_msg "======="

ip --brief a | while read -r DEV ; do
   log_msg "$DEV"
done
log_msg

dump_user_settings

log_msg

gen_working_VPN_file

setup_kill_switch

if is_enabled "$HTTP_PROXY" ; then
   log_msg "Backgrounding HTTP proxy ..."
   scripts/run-http-proxy.sh &
fi

if is_enabled "$SOCKS_PROXY" ; then
   log_msg "Backgrounding SOCKS proxy ..."
   scripts/run-socks-proxy.sh &
fi

# Our trap handles gracefully terminating openvpn
trap 'log_msg "Caught container exit signal"; cleanup; log_msg "Bye."; exit 0' SIGTERM

log_msg "Backgrounding openvpn ..."
OPENVPN_ARGS=(
   "--config" "$MODIFIED_CONFIG_FILE"
   "--auth-nocache"
   "--cd" "vpn"
   "--pull-filter" "ignore" "ifconfig-ipv6 "
   "--pull-filter" "ignore" "route-ipv6 "
   "--script-security" "2"
   "--data-ciphers-fallback" "AES-256-CBC"
   "--connect-retry" "${RETRY:-5}" "${MAX_RETRY:-60}"
   "--server-poll-timeout" "${SERVER_POLL:-120}"
   "--ping" "${PING:-15}"
   "--ping-restart" "${PING_RESTART:-120}"
   "--up-restart"
   "--mute-replay-warnings"
   "--comp-lzo" "no"
   "--verb" "$VPN_LOG_LEVEL"
)

if is_enabled "$USE_FAST_IO" ; then
   OPENVPN_ARGS+=(
      "--fast-io"
   )
fi

if [[ -n "$SNDBUF" ]] ; then
   OPENVPN_ARGS+=(
      "--sndbuf" "${SNDBUF}"
   )
fi

if [[ -n "$RCVBUF" ]] ; then
   OPENVPN_ARGS+=(
      "--rcvbuf" "${RCVBUF}"
   )
fi

if is_enabled "$USE_VPN_DNS" ; then
   OPENVPN_ARGS+=(
      "--up" "/etc/openvpn/up.sh"
      "--down" "/etc/openvpn/down.sh"
   )
fi

if [[ $VPN_AUTH_SECRET ]]; then
   OPENVPN_ARGS+=("--auth-user-pass" "/run/secrets/$VPN_AUTH_SECRET")
fi

openvpn "${OPENVPN_ARGS[@]}" &
OPENVPN_CHILD=$!

wait $OPENVPN_CHILD

# Never reached
cleanup

log_msg "Bye."
exit 0
