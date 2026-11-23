# Part 2: Discovering a VXLAN

## The goal

We have two hosts, each one behind its own router. We want the two hosts to
behave **as if they were plugged into the same switch**, even though there are
routers between them.

To do this we use a **VXLAN** (RFC 7348) with the ID **10**. We set it up in two
ways:

1. **Static mode:** each router is told the address of the other router.
2. **Multicast mode:** the routers find each other on their own, by joining a
   multicast group (`239.1.1.1`).

## The topology

```
                          10.1.1.0/24  (underlay)
                   eth0 ┌──────────┐ eth0
          ┌─────────────┤ Switch1  ├─────────────┐
          │  10.1.1.1   └──────────┘   10.1.1.2  │
 ┌────────┴──────────┐                 ┌─────────┴─────────┐
 │routeur-ncardozo-1 │                 │routeur-ncardozo-2 │
 │  br0 + vxlan10    │                 │  br0 + vxlan10    │
 └────────┬──────────┘                 └─────────┬─────────┘
          │ eth1                                 │ eth1
          │ eth1                                 │ eth1
 ┌────────┴──────────┐                 ┌─────────┴─────────┐
 │  host-ncardozo-1  │                 │  host-ncardozo-2  │
 │    30.1.1.1/24    │                 │    30.1.1.2/24    │
 └───────────────────┘                 └───────────────────┘

          └───────── same Layer 2 network: 30.1.1.0/24 (VXLAN 10) ─────────┘
```

All machines use the images from Part 1 (`badass-routeur` and `badass-host`).

## Words you need to know

| Word            | Simple meaning                                                                 |
|-----------------|--------------------------------------------------------------------------------|
| **Underlay**    | The "real" network the routers use to talk to each other (`10.1.1.0/24`).     |
| **Overlay**     | The virtual network built on top of it, used by the hosts (`30.1.1.0/24`).   |
| **VXLAN**       | A tunnel that puts whole Ethernet frames inside UDP packets (port `4789`).   |
| **VNI**         | The VXLAN ID. Here it is `10`. Both routers must use the same one.           |
| **VTEP**        | A device that opens and closes the tunnel. Here, each router is a VTEP.      |
| **Bridge**      | A software switch inside the router (`br0`).                                  |
| **Multicast**   | Sending one packet to a group of machines instead of a single one.           |

**How a packet travels:** host 1 sends a frame → router 1's bridge `br0` passes it
to `vxlan10` → `vxlan10` wraps it in a UDP packet and sends it to router 2 →
router 2 unwraps it → its bridge passes it to host 2.

## Files in this folder

The file names follow the pattern `_<login>-<number>_<type>`:

| File                          | Machine              | Mode                 |
|-------------------------------|----------------------|----------------------|
| `_ncardozo-1_host`            | `host-ncardozo-1`    | both modes           |
| `_ncardozo-2_host`            | `host-ncardozo-2`    | both modes           |
| `_ncardozo-1_s`               | `routeur-ncardozo-1` | static (`s`)         |
| `_ncardozo-2_s`               | `routeur-ncardozo-2` | static (`s`)         |
| `_ncardozo-1_g`               | `routeur-ncardozo-1` | multicast group (`g`)|
| `_ncardozo-2_g`               | `routeur-ncardozo-2` | multicast group (`g`)|
| `P2.gns3project`              | all machines         | the GNS3 project, exported as a ZIP file |

The hosts do not change between the two modes. Only the routers do.

## What each file does

### Hosts

```sh
ip addr add 30.1.1.1/24 dev eth1     # 30.1.1.2/24 on host 2
```

A host only needs an address. It does not know that a tunnel exists.

### Routers, static mode (`_s`)

```sh
ip addr add 10.1.1.1/24 dev eth0                    # 1. underlay address
ip link add br0 type bridge                         # 2. create the bridge
ip link set br0 up
ip link add vxlan10 type vxlan id 10 dev eth0 \
    local 10.1.1.1 remote 10.1.1.2 dstport 4789     # 3. create the tunnel
ip link set vxlan10 up
ip link set eth1 master br0                         # 4. plug the host port
ip link set vxlan10 master br0                      #    and the tunnel into the bridge
```

`remote 10.1.1.2` is written by hand: router 1 always sends tunnel traffic to
router 2. Router 2 has the same file with the two addresses swapped.

### Routers, multicast mode (`_g`)

The only line that changes is the tunnel:

```sh
ip link add vxlan10 type vxlan id 10 dev eth0 group 239.1.1.1 dstport 4789
```

There is no `remote` address. When a router does not know where a host is, it
sends the packet to the group `239.1.1.1`, and every router in the group receives
it. When the answer comes back, the router learns which router is behind
which host, and then sends directly to it.

## How to run it

1. In GNS3, choose *File → Import portable project* and pick `P2/P2.gns3project`.
2. Start all the machines with the green ▶ button.
3. On each machine, open the console (*right click → Console*) and paste the
   content of its file:
   - hosts: `_ncardozo-1_host` and `_ncardozo-2_host`
   - routers: the two `_s` files **or** the two `_g` files

> The settings are lost when a machine is stopped. Paste the files again after
> each restart.

**To switch from static to multicast:** stop and start the two routers (this
erases their settings), then paste the `_g` files. The hosts can stay as they are.

## How to check that it works

**1. The hosts can reach each other.** On `host-ncardozo-1`:

```sh
ping 30.1.1.2
```

**2. The tunnel is set up correctly.** On a router:

```sh
ip -d link show vxlan10
```

Look for `vxlan id 10`, then `remote 10.1.1.2` in static mode, or
`group 239.1.1.1` in multicast mode.

**3. The router joined the group** (multicast mode only):

```sh
ip maddr show dev eth0     # 239.1.1.1 is in the list
```

**4. The MAC address table.** On a router, while the ping is running:

```sh
bridge fdb show br br0
```

You see the MAC address of the local host (on `eth1`) and of the remote host
(on `vxlan10`). The remote host's entry shows the other router's address
(`dst 10.1.1.x`): this is what the router has learned.

**5. Watch the traffic in Wireshark.** In GNS3, right click the link between a
router and `Switch1` → **Start capture**, then ping between the hosts. You see:

- **UDP** packets on port **4789**, shown as **VXLAN** with **VNI 10**,
- the outside addresses are the routers (`10.1.1.1` ↔ `10.1.1.2`),
- the inside addresses are the hosts (`30.1.1.1` ↔ `30.1.1.2`, ICMP).

In multicast mode, the first packets (ARP, "who has 30.1.1.2?") are sent to
`239.1.1.1`. After that, the routers send to each other directly.
