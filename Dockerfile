FROM alpine:3.11.6

LABEL maintainer="yacht7@protonmail.com"

ENV KILL_SWITCH=on

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

ENTRYPOINT ["/data/entry.sh"]
