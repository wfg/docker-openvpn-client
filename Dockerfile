FROM alpine:3.10

LABEL maintainer="yacht7"

RUN \
    apk add --no-cache \
        openvpn \
        tinyproxy && \
    mkdir -p /data/vpn /var/log/openvpn
COPY data/ /data
RUN chmod 500 /data/entry.sh && \
    mv /data/tinyproxy.conf /etc/tinyproxy/tinyproxy.conf

HEALTHCHECK CMD ping -qc 3 1.1.1.1

ENTRYPOINT ["/data/entry.sh"]