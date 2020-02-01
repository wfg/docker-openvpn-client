# OpenVPN Client for Docker
## Why?
Using this image will allow you establish a VPN connection usable by other containers without having to install a VPN client on the host. The image requires the user to supply the needed OpenVPN configuration files, so (probably) any VPN provider will work.

It has a VPN killswitch, so if the VPN connection is lost at any time, all internet connectivity to this and connected containers is lost.

Please note that the killswitch does allow connections to the VPN server address/port combinations specified in the configuration file in order to establish connection.

## Creating
### `docker run`
```
docker run -d \
  --name=openvpn-client \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -v <path/to/config>:/data/vpn
  yacht7/openvpn-client
```

### `docker-compose`
```
version: '2'

services:
    openvpn-client:
        image: yacht7/openvpn-client
        container_name: openvpn-client
        cap_add:
            - NET_ADMIN
        devices:
            - /dev/net/tun
        volumes:
            - <path/to/config>:/data/vpn
        restart: unless-stopped
```
#### Considerations
##### Tinyproxy
If enabling Tinyproxy, you'll want to publish port 8888 to access the proxy. To do that, add `-p 8888:8888` if you're using `docker run`, or add the below snippet to the `openvpn-client` service definition in your Compose file if using `docker-compose`.
```
ports:
    - 8888:8888
```

##### Handling ports intended for connected containers
If you plan on having [other containers use `openvpn-client`'s network stack](#using-with-other-containers) and those containers have web UIs, you'll want to publish the web UI ports on `openvpn-client` instead of the connected container. To do that, add `-p <host_port>:<container_port>` if you're using `docker run`, or add the below snippet to the `openvpn-client` service definition in your Compose file if using `docker-compose`.
```
ports:
    - <host_port>:<container_port>
```
In both cases, replace `<host_port>` and `<container_port>` with the port used by your connected container.

### Environment variables

| Variable | Default (blank is unset) | Description |
| --- | --- | --- |
| `FORWARDED_PORTS` | | Port(s) forwarded by your VPN provider (e.g. `12345` or `9876,54321`) |
| `LOG_LEVEL` | `3` | OpenVPN verbosity (`1`-`11`) |
| `SUBNETS` | | A comma-separated (no whitespaces) list of LAN subnets (e.g. `192.168.0.0/24,192.168.1.0/24`) |
| `TINYPROXY` | | The on/off status of the forward proxy; to enable, set to `on`. Any other value, including leaving it unset, will cause the proxy to not start. |
| `TINYPROXY_PORT` | `8888` | The port that Tinyproxy listens on. If manually specified, choose a port over 1024. |
| `TINYPROXY_USER` | | Setting `TINYPROXY_USER` and `TINYPROXY_PASS` will restrict access to the proxy server to only the specified username and password. |
| `TINYPROXY_PASS` | | Setting `TINYPROXY_USER` and `TINYPROXY_PASS` will restrict access to the proxy server to only the specified username and password. |

#### `SUBNETS`
The subnets specified will have routes created and whitelists added in the firewall for them which allows for connectivity to and from hosts on the subnets. 

## Running
### Verifying functionality
Once you have container running `yacht7/openvpn-client`, run the following command to spin up a temporary container using `openvpn-client` for networking. The `wget -qO - ifconfig.me` bit will return the public IP of the container (and anything else using `openvpn-client` for networking). You should see an IP address owned by your VPN provider.
```
docker run --rm -it --network=container:openvpn-client alpine wget -qO - ifconfig.me
```

### Using with other containers
Once you have your OpenVPN client container up and running, you can tell other containers to use `openvpn-client`'s network stack which gives any container the ability to utilize the VPN tunnel. There are a few ways to accomplish this depending how how your container is created.

If your container is being created with
1. the same Compose YAML file as `openvpn-client`, add `network_mode: service:openvpn-client` to the container's service definition.
2. a different Compose YAML file as `openvpn-client`, add `network_mode: container:openvpn-client` to the container's service definition.
3. `docker run`, add `--network=container:openvpn-client` as an option to `docker run`.

Once running and provided your container has `wget` or `curl`, you can run `docker exec <container_name> wget -qO - ifconfig.me` or `docker exec <container_name> curl -s ifconfig.me` to get the public IP of the container and make sure everything is working as expected. This IP should match the one of `openvpn-client`.

If the connected container needs to publish ports, see [this](#handling-ports-intended-for-connected-containers) section.
