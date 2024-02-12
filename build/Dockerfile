FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    bind-tools \
    iptables \
    ip6tables \
    openvpn

COPY . /usr/local/bin

ENV KILL_SWITCH=on

ENTRYPOINT [ "entry.sh" ]
