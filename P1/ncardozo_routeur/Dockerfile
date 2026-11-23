# Router image: FRRouting on Alpine Linux, with BusyBox included
FROM quay.io/frrouting/frr:10.7.1

# Enable the routing services required by the subject: BGP, OSPF and IS-IS
RUN sed -i  -e 's/^bgpd=no/bgpd=yes/' \
            -e 's/^ospfd=no/ospfd=yes/' \
            -e 's/^isisd=no/isisd=yes/' /etc/frr/daemons

# Create the configuration file expected by vtysh, the FRR shell
RUN touch /etc/frr/vtysh.conf
