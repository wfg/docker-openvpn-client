FROM alpine:3.13.1 AS build

ARG DANTE_VERSION=1.4.2

RUN apk add --no-cache build-base
RUN wget https://www.inet.no/dante/files/dante-$DANTE_VERSION.tar.gz --output-document - | tar -xz \
    && cd dante-$DANTE_VERSION \
    && ac_cv_func_sched_setscheduler=no ./configure --disable-client \
    && make install


FROM alpine:3.13.1

ARG IMAGE_VERSION
ARG BUILD_DATE

LABEL source="github.com/wfg/docker-openvpn-client"
LABEL version="$IMAGE_VERSION"
LABEL created="$BUILD_DATE"

COPY --from=build /usr/local/sbin/sockd /usr/local/sbin/sockd

ENV KILL_SWITCH=on \
    VPN_LOG_LEVEL=3 \
    HTTP_PROXY=off \
    SOCKS_PROXY=off

RUN apk add --no-cache \
        bind-tools \
        openvpn \
        tinyproxy

RUN mkdir -p /data/vpn \
    && addgroup -S socks \
    && adduser -S -D -G socks -g "socks" -H -h /dev/null socks

COPY data/ /data

HEALTHCHECK CMD ping -c 3 1.1.1.1 || exit 1

ENTRYPOINT ["/data/scripts/entry.sh"]
