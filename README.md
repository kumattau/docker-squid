# docker-squid

Dockerfile to create [squid](http://www.squid-cache.org/) proxy server image

## Purpose

Many websites only accept TLS 1.2 or later of HTTPS,
so very old OS released before TLS 1.2 such as RHEL3 cannot access these sites without upgrading TLS version.

```
bash-2.05b# cat /etc/redhat-release 
CentOS release 3.8 (Final)
bash-2.05b# curl -I https://github.com
curl: (35) SSL: error:1407742E:SSL routines:SSL23_GET_SERVER_HELLO:tlsv1 alert protocol version
```

This proxy server enables the very old OS to access these sites by upgrading TLS version to 1.3 with ssl-bump.

## Feature

* Installed squid 6.6 with most functions
* Supported TLS 1.0 and TLS 1.1 for old clients
* Supported both ssl-bump and cache_peer (forward to upstream proxy)
* Based on Rocky Linux 8, which is supported until May 31, 2029
* But relatively small image (smaller than 100MiB)

## Usage

Start proxy server.

```
$ docker compose up
docker-squid-squid-1  | 2024/01/14 14:52:49| Accepting SSL bumped HTTP Socket connections at conn12 local=0.0.0.0:3128 remote=[::] FD 22 flags=9
docker-squid-squid-1  |     listening port: 3128
```

Access the sites via the proxy (`172.17.0.1` needs to be replaced with your ip address).

```
bash-2.05b# cat /etc/redhat-release 
CentOS release 3.8 (Final)
bash-2.05b# https_proxy=http://172.17.0.1:3128 curl -I --insecure https://github.com
HTTP/1.1 200 OK
Server: GitHub.com
...
```

As default, ssl-bump uses a self-signed certificate in `/usr/local/squid/var/lib/squid/ssl-bump.pem` generated at build time.

See [docker-compose.yml](docker-compose.yml), [squid.conf](squid.conf) and [Dockerfile](Dockerfile) for more details.

## Notice

* This is not ready for production use.
* Dockerfile is under MIT license, but the docker image created by Dockerfile contains
  [squid](http://www.squid-cache.org/), [busybox:musl](https://hub.docker.com/_/busybox) and [rockylinux:8](https://hub.docker.com/_/rockylinux).
