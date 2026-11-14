# Part 1: GNS3 configuration with Docker

## The goal

In this part we build the **two Docker images** used for the whole project, then
run them in GNS3:

| Image           | Role       | What it contains                                   |
|-----------------|------------|----------------------------------------------------|
| `badass-host`   | A computer | Alpine Linux, which includes BusyBox               |
| `badass-router` | A router   | FRRouting with zebra, BGP, OSPF and IS-IS enabled  |

GNS3 uses these images to create the machines. Every machine name contains the
login `ncardozo`, as the subject requires.

```
 ┌────────────────────┐      ┌────────────────────┐
 │  host-ncardozo-1   │      │  router-ncardozo   │
 │  (badass-host)     │      │  (badass-router)   │
 └────────────────────┘      └────────────────────┘
```

The two machines are not connected yet. Here we only check that they both start
and that we can open a terminal on them. Parts 2 and 3 will connect them.

## Files in this folder

| File                          | What it is                                             |
|-------------------------------|--------------------------------------------------------|
| `ncardozo_host/Dockerfile`    | Recipe for the host image                              |
| `ncardozo_router/Dockerfile`  | Recipe for the router image                            |
| `P1.gns3project`              | The GNS3 project, exported as a ZIP file               |

## The two images, explained

### The host: `ncardozo_host/Dockerfile`

```dockerfile
FROM alpine:3.23
CMD ["/bin/sh"]
```

- **Alpine** is a very small Linux system. It already includes **BusyBox**, a
  single program that provides the basic commands (`ls`, `ping`, `ip`, `sh`...).
- `CMD ["/bin/sh"]` opens a shell when the machine starts, so GNS3 has a
  terminal to show you.

### The router: `ncardozo_router/Dockerfile`

```dockerfile
FROM quay.io/frrouting/frr:10.7.1
RUN sed -i -e 's/^bgpd=no/bgpd=yes/' \
           -e 's/^ospfd=no/ospfd=yes/' \
           -e 's/^isisd=no/isisd=yes/' /etc/frr/daemons
RUN touch /etc/frr/vtysh.conf
```

- **FRRouting (FRR)** is routing software. It is the modern version of Quagga.
  Its official image is based on Alpine, so it also includes BusyBox.
- FRR is made of small programs called *daemons*, one per job:
  - `zebra` puts the routes into the system. It always runs.
  - `bgpd` runs **BGP**, the routing protocol of the Internet.
  - `ospfd` runs **OSPF**, a routing protocol used inside a network.
  - `isisd` runs **IS-IS**, another routing protocol used inside a network.
- By default, the daemons are turned off in `/etc/frr/daemons`. The `sed` command
  changes `bgpd=no` to `bgpd=yes`, and does the same for OSPF and IS-IS.
- `vtysh` is the FRR command shell. It looks for `/etc/frr/vtysh.conf`, so we
  create an empty one to avoid a warning.

> **No IP address is set in the images.** The subject asks for this, because
> each part of the project gives the machines different addresses.

## How to build the images

From the root of the repository:

```bash
make P1
```

This builds both images and shows them at the end. You can also build them by
hand:

```bash
docker build -t badass-host   P1/ncardozo_host
docker build -t badass-router P1/ncardozo_router
docker images | grep badass
```

Other useful commands:

| Command       | What it does                                              |
|---------------|-----------------------------------------------------------|
| `make save`   | Saves both images into `P1/badass-images.tar.gz`          |
| `make load`   | Loads the images back from that archive, without building |
| `make cleanP1`| Removes the containers and the two images                 |

## How to use them in GNS3

**The quick way:** in GNS3, choose *File → Import portable project* and pick
`P1/P1.gns3project`.

**By hand:**

1. Go to *Edit → Preferences → Docker → Docker containers → New*.
2. Choose the `badass-host:latest` image, and select **telnet** as the console type.
3. Do the same for `badass-router:latest`.
4. Drag one host and one router into the project.
5. Rename them (*right click → Change hostname*) to `host-ncardozo-1` and
   `router-ncardozo`.
6. Click the green ▶ button to start them.
7. Right click a machine → **Console** to open its terminal.

## How to check that it works

On the **host**, try a few BusyBox commands:

```sh
busybox | head -1      # shows the BusyBox version
ip addr                # only "lo" has an address: no IP is set by default
```

On the **router**, check that the daemons are running:

```sh
ps                     # look for zebra, bgpd, ospfd, isisd (and watchfrr)
vtysh                  # opens the FRR shell
show running-config    # inside vtysh: the current configuration
exit
```

If you see `zebra`, `bgpd`, `ospfd` and `isisd` in the list, the router image is ready.
