#Alpine contient deja BusyBox.
FROM alpine:3.23

#Outils pour configurer et observer le reseau.
RUN apk add --no-cache iproute2 iputils tcpdump

#Ouvrir un shell au demarrage du conteneur.
CMD ["/bin/sh"]
