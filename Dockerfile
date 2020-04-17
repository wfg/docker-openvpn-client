FROM alpine:3.10

LABEL maintainer="yacht7"

ENV KILL_SWITCH=on

RUN \
    echo '@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories && \
    apk add --no-cache \
        openvpn \
        shadowsocks-libev@testing \
        tinyproxy && \
    mkdir -p /data/vpn /var/log/openvpn && \
    addgroup -S shadowsocks && \
    adduser -S -G shadowsocks -g "shadowsocks user" -H -h /dev/null shadowsocks
COPY data/ /data
RUN chmod 500 /data/entry.sh

HEALTHCHECK CMD ping -qc 3 1.1.1.1

ENTRYPOINT ["/data/entry.sh"]