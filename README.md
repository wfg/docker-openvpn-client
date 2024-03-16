# OpenVPN Client for Docker

Archived in favor of [a WireGuard version](https://github.com/wfg/docker-wireguard).

## What is this and what does it do?
[`ghcr.io/wfg/openvpn-client`](https://github.com/users/wfg/packages/container/package/openvpn-client) is a containerized OpenVPN client.
It has a kill switch built with `iptables` that kills Internet connectivity to the container if the VPN tunnel goes down for any reason.

This image requires you to supply the necessary OpenVPN configuration file(s).
Because of this, any VPN provider should work.

If you find something that doesn't work or have an idea for a new feature, issues and **pull requests are welcome** (however, I'm not promising they will be merged).

## Why?
Having a containerized VPN client lets you use container networking to easily choose which applications you want using the VPN instead of having to set up split tunnelling.
It also keeps you from having to install an OpenVPN client on the underlying host.

## How do I use it?
### Getting the image
You can either pull it from GitHub Container Registry or build it yourself.

To pull it from GitHub Container Registry, run
```
docker pull ghcr.io/wfg/openvpn-client
```

To build it yourself, run
```
docker build -t ghcr.io/wfg/openvpn-client https://github.com/wfg/docker-openvpn-client.git#:build
```

### Creating and running a container
The image requires the container be created with the `NET_ADMIN` capability and `/dev/net/tun` accessible.
Below are bare-bones examples for `docker run` and Compose; however, you'll probably want to do more than just run the VPN client.
See the below to learn how to have [other containers use `openvpn-client`'s network stack](#using-with-other-containers).

#### `docker run`
```
docker run --detach \
  --name=openvpn-client \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  --volume <path/to/config/dir>:/config \
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
      - <path/to/config/dir>:/config
    restart: unless-stopped
```

#### Environment variables
| Variable | Default (blank is unset) | Description |
| --- | --- | --- |
| `ALLOWED_SUBNETS` | | A list of one or more comma-separated subnets (e.g. `192.168.0.0/24,192.168.1.0/24`) to allow outside of the VPN tunnel. |
| `AUTH_SECRET` | | Docker secret that contains the credentials for accessing the VPN. |
| `CONFIG_FILE` | | The OpenVPN configuration file or search pattern. If unset, a random `.conf` or `.ovpn` file will be selected. |
| `KILL_SWITCH` | `on` | Whether or not to enable the kill switch. Set to any "truthy" value[1] to enable. |

[1] "Truthy" values in this context are the following: `true`, `t`, `yes`, `y`, `1`, `on`, `enable`, or `enabled`.

##### Environment variable considerations
###### `ALLOWED_SUBNETS`
If you intend on connecting to containers that use the OpenVPN container's network stack (which you probably do), **you will probably want to use this variable**.
Regardless of whether or not you're using the kill switch, the entrypoint script also adds routes to each of the `ALLOWED_SUBNETS` to allow network connectivity from outside of Docker.

##### `AUTH_SECRET`
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
```
docker run --rm -it --network=container:openvpn-client alpine wget -qO - ifconfig.me
```

### Troubleshooting
#### VPN authentication
Your OpenVPN configuration file may not come with authentication baked in.
To provide OpenVPN the necessary credentials, create a file (any name will work, but this example will use `credentials.txt`) next to the OpenVPN configuration file with your username on the first line and your password on the second line.

For example:
```
vpn_username
vpn_password
```

In the OpenVPN configuration file, add the following line:
```
auth-user-pass credentials.txt
```

This will tell OpenVPN to read `credentials.txt` whenever it needs credentials.
