# OpenVPN Client for Docker
## What is this and what does it do?
[`yacht7/openvpn-client`](https://hub.docker.com/r/yacht7/openvpn-client) is a containerized OpenVPN client. It has a kill switch built with `iptables` that kills Internet connectivity to the container if the VPN tunnel goes down for any reason. It also includes two types of proxy: HTTP (Tinyproxy) and SOCKS5 (Shadowsocks). These allow hosts and non-containerized applications to use the VPN without having to run VPN clients on every host.

This image requires you to supply the necessary OpenVPN configuration file(s). Because of this, any VPN provider should work (however, if you find something that doesn't, please open an issue for it).

## Why?
Having a containerized VPN client lets you use container networking to easily choose which applications you want using the VPN instead of having to set up split tunnelling. It also keeps you from having to install an OpenVPN client on the underlying host.

The idea for this image came from a similar project by [qdm12](https://github.com/qdm12) that has since evolved into something bigger and more complex than I wanted to use. I decided to dissect it and take it in my own direction. I plan to keep everything here well-documented because I want this to be a learning experience for both me and hopefully anyone else that uses it.

## How do I use it?
### Getting the image
You can either pull it from Docker Hub or build it yourself.

To pull from [Docker Hub](https://hub.docker.com/r/yacht7/openvpn-client), run `docker pull yacht7/openvpn-client`.

To build it yourself, do the following:
```bash
git clone https://github.com/yacht7/docker-openvpn-client.git
cd docker-openvpn-client
docker build -t yacht7/openvpn-client .
```

### Creating and running a container
The image requires the container be created with the `NET_ADMIN` capability and `/dev/net/tun` accessible. Below are bare-bones examples for `docker run` and Compose; however, you'll probably want to do more than just run the VPN client. See the sections below to learn how to use the [proxies](#shadowsocks-and-tinyproxy) and have [other containers use `openvpn-client`'s network stack](#using-with-other-containers).

#### `docker run`
```bash
docker run -d \
  --name=openvpn-client \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -v <path/to/config>:/data/vpn
  yacht7/openvpn-client
```

#### `docker-compose`
```yaml
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

#### Environment variables
| Variable | Default (blank is unset) | Description |
| --- | --- | --- |
| `KILL_SWITCH` | `on` | The on/off status of VPN kill switch. To disable, set to any value besides `on`. |
| `SUBNETS` | | A list of one or more comma-separated subnets (e.g. `192.168.0.0/24,192.168.1.0/24`) to allow outside of the VPN tunnel. See important note about this [below](#subnets). |
| `FORWARDED_PORTS` | | Port(s) forwarded by your VPN provider (e.g. `12345` or `9876,54321`) |
| `VPN_LOG_LEVEL` | `3` | OpenVPN verbosity (`1`-`11`) |
| `SHADOWSOCKS` | | The on/off status of Shadowsocks. To enable, set to `on`. Any other value, including leaving it unset, will cause the proxy to not start. |
| `SHADOWSOCKS_PORT` | `8388` | The port on which Shadowsocks listens. If manually specified, choose a port over 1024. |
| `SHADOWSOCKS_PASS` | `password` | A password is required to start Shadowsocks, so a default is specified. I recommend you change this if Shadowsocks is enabled. |
| `TINYPROXY` | | The on/off status of Tinyproxy. To enable, set to `on`. Any other value, including leaving it unset, will cause the proxy to not start. |
| `TINYPROXY_PORT` | `8888` | The port on which Tinyproxy listens. If manually specified, choose a port over 1024. |
| `TINYPROXY_USER` | | Credentials for accessing Tinyproxy. If `TINYPROXY_USER` is specified, you must also specify `TINYPROXY_PASS`. |
| `TINYPROXY_PASS` | | Credentials for accessing Tinyproxy. If `TINYPROXY_PASS` is specified, you must also specify `TINYPROXY_USER`. |

##### Environment variable considerations
###### `KILL_SWITCH`
The kill switch allows connections outside of the VPN tunnel to the following two places: 1) the VPN server(s) specified in the configuration file and 2) all addresses specified in `SUBNETS`.

###### `SUBNETS`
**Important**: The DNS server used by this container prior to VPN connection must be included in the value specified. For example, if your container is using 192.168.1.1 as a DNS server, then this address or an appropriate CIDR block must be included in `SUBNETS`. This is necessary because the kill switch blocks traffic outside of the VPN tunnel before it's actually established. If the DNS server is not whitelisted, the server addresses in the VPN configuration will not resolve.

The subnets specified will have routes created and whitelists added in the firewall for them which allows for connectivity to and from hosts on the subnets.

###### `SHADOWSOCKS` and `TINYPROXY`
If enabling Shadowsocks or Tinyproxy, you'll want to publish the proxy's port in order to access the proxy. To do that using `docker run`, add `-p <host_port>:<container_port>` where `<host_port>` and `<container_port>` are whatever port your proxy is using (8388 and 8888 by default for Shadowsocks and Tinyproxy). If you're using `docker-compose`, add the below snippet to the `openvpn-client` service definition in your Compose file.
```yaml
ports:
    - <host_port>:<container_port>
```

### Using with other containers
Once you have your `openvpn-client` container up and running, you can tell other containers to use `openvpn-client`'s network stack which gives them the ability to utilize the VPN tunnel. There are a few ways to accomplish this depending how how your container is created.

If your container is being created with
1. the same Compose YAML file as `openvpn-client`, add `network_mode: service:openvpn-client` to the container's service definition.
2. a different Compose YAML file than `openvpn-client`, add `network_mode: container:openvpn-client` to the container's service definition.
3. `docker run`, add `--network=container:openvpn-client` as an option to `docker run`.

Once running and provided your container has `wget` or `curl`, you can run `docker exec <container_name> wget -qO - ifconfig.me` or `docker exec <container_name> curl -s ifconfig.me` to get the public IP of the container and make sure everything is working as expected. This IP should match the one of `openvpn-client`.

#### Handling ports intended for connected containers
If you have a connected container and you need to access a port that container, you'll want to publish that port on the `openvpn-client` container instead of the connected container. To do that, add `-p <host_port>:<container_port>` if you're using `docker run`, or add the below snippet to the `openvpn-client` service definition in your Compose file if using `docker-compose`.
```yaml
ports:
    - <host_port>:<container_port>
```
In both cases, replace `<host_port>` and `<container_port>` with the port used by your connected container.

### Verifying functionality
Once you have container running `yacht7/openvpn-client`, run the following command to spin up a temporary container using `openvpn-client` for networking. The `wget -qO - ifconfig.me` bit will return the public IP of the container (and anything else using `openvpn-client` for networking). You should see an IP address owned by your VPN provider.
```bash
docker run --rm -it --network=container:openvpn-client alpine wget -qO - ifconfig.me
```

