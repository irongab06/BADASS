# BADASS — P1

Auteur : gacavali

## Contenu

- _gacavali-1_host : Dockerfile de l’hôte host-gacavali-1 (Alpine).
- _gacavali-1 : Dockerfile du routeur router-gacavali-1 (Alpine avec FRRouting).
- start.sh : démarrage des services, puis du shell.
- frr.conf : configuration initiale BGP et OSPF.
- P1.gns3project : export ZIP avec topologie et images Docker.

Les services Zebra, BGP, OSPF et IS-IS démarrent automatiquement.
Aucune adresse IPv4 n’est préconfigurée sur les interfaces.
Les deux équipements ne sont pas reliés, comme sur le schéma du sujet.

## Construire les images

Depuis la racine du dépôt :

```bash
docker build -t badass-host:1.0 -f P1/_gacavali-1_host P1
docker build -t badass-router:1.0 -f P1/_gacavali-1 P1
```

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

Sur ARM64, reconstruire les images avec les deux commandes ci-dessus.
La sauvegarde fournie contient des images amd64.
