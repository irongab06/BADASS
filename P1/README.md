# BADASS — P1

## Contenu

- _gacavali-1_host : Dockerfile de l’hôte host-gacavali-1 (Alpine).
- _gacavali-2 : Dockerfile du routeur router-gacavali-2 (Alpine avec FRRouting).
- start.sh : démarrage des services, puis du shell.
- frr.conf : configuration initiale BGP et OSPF.
- Makefile : construction, chargement et suppression des deux images.
- check-env.sh : vérification de la machine (outils, Docker, groupes).
- P1.gns3project : export ZIP avec topologie et images Docker.

Les services Zebra, BGP, OSPF et IS-IS démarrent automatiquement.
Aucune adresse IPv4 n’est préconfigurée sur les interfaces.
Les deux équipements ne sont pas reliés, comme sur le schéma du sujet.

## Construire les images

Depuis la racine du dépôt :

```bash
docker build -t badass-host:1.0 -f P1/_gacavali-1_host P1
docker build -t badass-router:1.0 -f P1/_gacavali-2 P1
```

Ou, avec le Makefile :

| Commande | Effet |
|---|---|
| `make -C P1` | Construit les deux images. |
| `make -C P1 check` | Affiche les deux images et la ligne `router bgp` du routeur. |
| `make -C P1 env` | Vérifie les outils, le service Docker et les groupes de la machine. |
| `make -C P1 load` | Charge les deux images depuis `P1.gns3project`, sans réseau. |
| `make -C P1 clean` | Supprime les conteneurs créés à partir des deux images, puis les images. |
| `make -C P1 re` | Supprime puis reconstruit. |
| `make -C P1 help` | Affiche cette liste. |

## Restaurer sur une VM Linux amd64

Extraire la sauvegarde des images :

```bash
python3 -m zipfile -e P1.gns3project /tmp/badass-p1-import
docker image load -i /tmp/badass-p1-import/docker-images-amd64.tar
```

`make -C P1 load` lance ces deux commandes.

Importer ensuite P1.gns3project dans GNS3 avec
File → Import portable project.

Démarrer les deux équipements et ouvrir leurs consoles.

## Ajouter une image Docker dans GNS3 à la main

L’import du projet crée déjà les deux équipements. Pour en créer un depuis
zéro, il faut un modèle (template) par image :

1. Edit → Preferences → Docker containers → New.
2. Choisir « Existing image », puis l’image dans la liste.
3. Donner un nom, puis le nombre d’interfaces (adapters).
4. Laisser la commande de démarrage vide et la console sur telnet.
5. Valider : le modèle apparaît dans la liste des équipements, à glisser
   dans le projet.

| Image | Interfaces | Pourquoi |
|---|---|---|
| `badass-host:1.0` | 2 | En P2 et en P3, un hôte est branché sur `eth1`. |
| `badass-router:1.0` | 4 | En P3, le route reflector utilise `eth0`, `eth1` et `eth2`. |

## Vérifications

Sur l’hôte :

```sh
ip addr
```

Sur le routeur :

```sh
ps
vtysh -c "show running-config"
```

## Autre architecture

Sur ARM64, reconstruire les images avec les deux commandes ci-dessus.
La sauvegarde fournie contient des images amd64.
