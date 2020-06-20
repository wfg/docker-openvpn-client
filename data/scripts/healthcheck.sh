#!/bin/sh

sleep 10
while ping -c 3 1.1.1.1 > /dev/null 2>&1; do
    sleep 10
done
echo "ERROR: Failed ping healthcheck. Exiting."

kill -- -1