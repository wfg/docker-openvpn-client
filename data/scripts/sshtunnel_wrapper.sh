#!/bin/bash

echo -e "Running SSH Tunnel.\n"

until ip link show tun0 2>&1 | grep -qv "does not exist"; do
    sleep 1
done

passwd -d root
adduser -D -s /bin/ash tunnel
passwd -d tunnel
chown -R tunnel:tunnel /home/tunnel
ssh-keygen -A
mkdir /home/tunnel/.ssh
cp /data/ssh/id_rsa.pub /home/tunnel/.ssh/authorized_keys

/usr/sbin/sshd -D
