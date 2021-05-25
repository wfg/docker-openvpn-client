FROM alpine:3.13 AS build

RUN echo "https://dl-cdn.alpinelinux.org/alpine/v3.13/community" >> /etc/apk/repositories

FROM alpine:3.13

ARG IMAGE_VERSION
ARG BUILD_DATE

LABEL source="github.com/wfg/docker-openvpn-client"
LABEL version="$IMAGE_VERSION"
LABEL created="$BUILD_DATE"

ENV KILL_SWITCH=on \
    VPN_LOG_LEVEL=3 \
    HTTP_PROXY=off \
    SOCKS_PROXY=off

RUN apk add --no-cache \
        bind-tools \
        openvpn \
        tinyproxy \
        dante-server

RUN mkdir -p /data/vpn

COPY data/ /data

HEALTHCHECK CMD ping -c 3 1.1.1.1 || exit 1

ENTRYPOINT ["/data/scripts/entry.sh"]
