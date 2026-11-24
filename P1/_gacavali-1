#Systeme leger contenant BusyBox.
FROM alpine:3.23

#Outils reseau et suite de routage FRRouting
RUN apk add --no-cache iproute2 iputils tcpdump frr

# Activer les trois services de routage demandes en P1.
RUN sed -i \
    -e 's/^bgpd=no$/bgpd=yes/' \
    -e 's/^ospfd=no$/ospfd=yes/' \
    -e 's/^isisd=no$/isisd=yes/' \
    /etc/frr/daemons

# Ajouter notre script de demarrage et autoriser son execution.
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Installer la configuration commune de FRRouting.
COPY frr.conf /etc/frr/frr.conf
RUN chown frr:frr /etc/frr/frr.conf \
    && chmod 640 /etc/frr/frr.conf

# Demarrer les services, puis ouvrir le shell.
CMD ["/usr/local/bin/start.sh"]
