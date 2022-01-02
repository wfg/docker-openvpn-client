# OpenVPN Client for Docker
## What is this and what does it do?
[`ghcr.io/wfg/openvpn-client`](https://github.com/users/wfg/packages/container/package/openvpn-client) is a containerized OpenVPN client.
It has a kill switch built with `iptables` that kills Internet connectivity to the container if the VPN tunnel goes down for any reason.
It also includes an HTTP proxy server ([Tinyproxy](https://tinyproxy.github.io/)) and a SOCKS proxy server ([Dante](https://www.inet.no/dante/index.html)).
This allows hosts and non-containerized applications to use the VPN without having to run VPN clients on those hosts.

This image requires you to supply the necessary OpenVPN configuration file(s).
Because of this, any VPN provider should work.

If you find something that doesn't work or have an idea for a new feature, issues and **pull requests are welcome**.

## Why?
Having a containerized VPN client lets you use container networking to easily choose which applications you want using the VPN instead of having to set up split tunnelling.
It also keeps you from having to install an OpenVPN client on the underlying host.

The idea for this image came from a similar project by [qdm12](https://github.com/qdm12) that has since evolved into something bigger and more complex than I wanted to use.
I decided to dissect it and take it in my own direction.
I plan to keep everything here well-documented so this is not only a learning experience for me, but also anyone else that uses it.

## How do I use it?
### Getting the image
You can either pull it from GitHub Container Registry or build it yourself.

To pull it from GitHub Container Registry, run
```bash
docker pull ghcr.io/wfg/openvpn-client
```

To build it yourself, run
```bash
docker build -t ghcr.io/wfg/openvpn-client https://github.com/wfg/docker-openvpn-client.git
```

### Creating and running a container
The image requires the container be created with the `NET_ADMIN` capability and `/dev/net/tun` accessible.
Below are bare-bones examples for `docker run` and Compose; however, you'll probably want to do more than just run the VPN client.
See the sections below to learn how to use the [proxies](#http_proxy-and-socks_proxy) and have [other containers use `openvpn-client`'s network stack](#using-with-other-containers).

#### `docker run`
```bash
docker run --detach \
  --name=openvpn-client \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  --volume <path/to/config/dir>:/data/vpn \
  ghcr.io/wfg/openvpn-client
```

#### `docker-compose`
```yaml
services:
  openvpn-client:
    image: ghcr.io/wfg/openvpn-client
    container_name: openvpn-client
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    volumes:
      - <path/to/config/dir>:/data/vpn
    restart: unless-stopped
```

#### Environment variables (alphabetical)
| Variable | Default (blank is unset) | Description |
| --- | --- | --- |
| `HTTP_PROXY` | `off` | The on/off status of Tinyproxy, the built-in HTTP proxy server. To enable, set to `on`. Any other value (including unset) will cause the proxy server to not start. It listens on port 8080. |
| `KILL_SWITCH` | `on` | The on/off status of the network kill switch. |
| `LISTEN_ON` | | Address the proxies will be listening on. Set to `0.0.0.0` to listen on all IP addresses. |
| `PROXY_PASSWORD` | | Credentials for accessing the proxies. If `PROXY_PASSWORD` is specified, you must also specify `PROXY_USERNAME`. |
| `PROXY_PASSWORD_SECRET` | | Docker secrets that contain the credentials for accessing the proxies. If `PROXY_PASSWORD_SECRET` is specified, you must also specify `PROXY_USERNAME_SECRET`. |
| `PROXY_USERNAME` | | Credentials for accessing the proxies. If `PROXY_USERNAME` is specified, you must also specify `PROXY_PASSWORD`. |
| `PROXY_USERNAME_SECRET` | | Docker secrets that contain the credentials for accessing the proxies. If `PROXY_USERNAME_SECRET` is specified, you must also specify `PROXY_PASSWORD_SECRET`. |
| `SOCKS_PROXY` | `off` | The on/off status of Dante, the built-in SOCKS proxy server. To enable, set to `on`. Any other value (including unset) will cause the proxy server to not start. It listens on port 1080. |
| `SUBNETS` | | A list of one or more comma-separated subnets (e.g. `192.168.0.0/24,192.168.1.0/24`) to allow outside of the VPN tunnel. |
| `VPN_AUTH_SECRET` | | Docker secret that contain the credentials for accessing the VPN. |
| `VPN_CONFIG_FILE` | | The OpenVPN config file to use. If this is unset, the first file with the extension .conf will be used. |
| `VPN_LOG_LEVEL` | `3` | OpenVPN verbosity (`1`-`11`) |

##### Environment variable considerations
###### `HTTP_PROXY` and `SOCKS_PROXY`
If enabling the the proxy server(s), you'll want to publish the appropriate port(s) in order to access the server(s).
To do that using `docker run`, add `-p <host_port>:8080` and/or `-p <host_port>:1080` where `<host_port>` is whatever port you want to use on the host.
If you're using `docker-compose`, add the relevant port specification(s) from the snippet below to the `openvpn-client` service definition in your Compose file.
```yaml
ports:
  - <host_port>:8080
  - <host_port>:1080
```

###### `PROXY_USERNAME_SECRET`, `PROXY_PASSWORD_SECRET`, and `VPN_AUTH_SECRET`
Compose has support for [Docker secrets](https://docs.docker.com/engine/swarm/secrets/#use-secrets-in-compose).
See the [Compose file](docker-compose.yml) in this repository for example usage of passing proxy credentials as Docker secrets.

### Using with other containers
Once you have your `openvpn-client` container up and running, you can tell other containers to use `openvpn-client`'s network stack which gives them the ability to utilize the VPN tunnel.
There are a few ways to accomplish this depending how how your container is created.

If your container is being created with
1. the same Compose YAML file as `openvpn-client`, add `network_mode: service:openvpn-client` to the container's service definition.
2. a different Compose YAML file than `openvpn-client`, add `network_mode: container:openvpn-client` to the container's service definition.
3. `docker run`, add `--network=container:openvpn-client` as an option to `docker run`.

Once running and provided your container has `wget` or `curl`, you can run `docker exec <container_name> wget -qO - ifconfig.me` or `docker exec <container_name> curl -s ifconfig.me` to get the public IP of the container and make sure everything is working as expected.
This IP should match the one of `openvpn-client`.

#### Handling ports intended for connected containers
If you have a connected container and you need to access a port that container, you'll want to publish that port on the `openvpn-client` container instead of the connected container.
To do that, add `-p <host_port>:<container_port>` if you're using `docker run`, or add the below snippet to the `openvpn-client` service definition in your Compose file if using `docker-compose`.
```yaml
ports:
  - <host_port>:<container_port>
```
In both cases, replace `<host_port>` and `<container_port>` with the port used by your connected container.

### Verifying functionality
Once you have container running `ghcr.io/wfg/openvpn-client`, run the following command to spin up a temporary container using `openvpn-client` for networking.
The `wget -qO - ifconfig.me` bit will return the public IP of the container (and anything else using `openvpn-client` for networking).
You should see an IP address owned by your VPN provider.
```bash
docker run --rm -it --network=container:openvpn-client alpine wget -qO - ifconfig.me
```
