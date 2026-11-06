# BADASS — P1

Auteur : gacavali

## Contenu

- host/Dockerfile : image Alpine pour les hôtes.
- router/Dockerfile : image Alpine avec FRRouting.
- router/start.sh : démarrage des services, puis du shell.
- router/frr.conf : configuration initiale BGP et OSPF.
- P1.gns3project : export ZIP avec topologie et images Docker.

Les services Zebra, BGP, OSPF et IS-IS démarrent automatiquement.
Aucune adresse IPv4 n’est préconfigurée sur les interfaces.

## Restaurer sur une VM Linux amd64

Extraire la sauvegarde des images :

```bash
python3 -m zipfile -e P1.gns3project /tmp/badass-p1-import
docker image load -i /tmp/badass-p1-import/docker-images-amd64.tar
```

Importer ensuite P1.gns3project dans GNS3 avec
File → Import portable project.

Démarrer les deux équipements et ouvrir leurs consoles.

## Vérifications

Sur l’hôte :

```sh
ip -br addr
```

Sur le routeur :

```sh
ps
vtysh -c "show running-config"
```

## Autre architecture

Sur ARM64, reconstruire les images depuis les Dockerfiles.
La sauvegarde fournie contient des images amd64.
