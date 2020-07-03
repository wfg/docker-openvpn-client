FROM alpine:3.12

LABEL maintainer="yacht7@protonmail.com"

ENV KILL_SWITCH=on\
    VPN_LOG_LEVEL=3

RUN \
    echo '@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories && \
    apk add --no-cache \
        bind-tools \
        openvpn \
        shadowsocks-libev@testing \
        tinyproxy

RUN \
    mkdir -p /data/vpn /var/log/openvpn && \
    addgroup -S shadowsocks && \
    adduser -S -G shadowsocks -g "shadowsocks user" -H -h /dev/null shadowsocks

COPY data/ /data

HEALTHCHECK CMD ping -c 3 1.1.1.1 || exit 1

ENTRYPOINT ["/data/scripts/entry.sh"]
