FROM alpine:3.16

RUN apk add --no-cache \
    bash \
    bind-tools \
    iptables \
    ip6tables \
    openvpn

COPY . /usr/local/bin

ENTRYPOINT [ "entry.sh" ]
