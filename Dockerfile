FROM alpine:3.16

RUN apk add --no-cache \
        bash \
        bind-tools \
        dante-server \
        iptables \
        openvpn \
        nftables \
        shadow \
        tinyproxy

COPY data/ /data/

ENV KILL_SWITCH=iptables
ENV USE_VPN_DNS=on
ENV VPN_LOG_LEVEL=3

ARG BUILD_DATE
ARG IMAGE_VERSION

LABEL build-date=$BUILD_DATE
LABEL image-version=$IMAGE_VERSION

HEALTHCHECK CMD ping -c 3 1.1.1.1 || exit 1

WORKDIR /data

ENTRYPOINT [ "scripts/entry.sh" ]
