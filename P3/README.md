# BADASS — P3

Un petit centre de données : un routeur central et trois routeurs de bord,
chacun avec un hôte. Les trois hôtes se parlent comme sur un seul switch,
à travers le VXLAN 10 de la P2. La nouveauté : les routeurs ne découvrent plus
les adresses MAC en inondant le réseau, ils se les annoncent avec BGP EVPN.

## Topologie

```
                      router-gacavali-1 (RR)
                          lo 1.1.1.1
              eth0 .1 /     eth1 .5 |     \ eth2 .9
        10.1.1.0/30  /  10.1.1.4/30 |      \  10.1.1.8/30
              eth0 .2       eth1 .6 |       eth2 .10
    router-gacavali-2   router-gacavali-3   router-gacavali-4
       lo 1.1.1.2          lo 1.1.1.3          lo 1.1.1.4
          eth1                eth0                eth0
           |                   |                   |
          eth1                eth0                eth0
     host-gacavali-1     host-gacavali-2     host-gacavali-3
       20.1.1.1/24         20.1.1.2/24         20.1.1.3/24
```

## Contenu

| Fichier | Équipement | Rôle |
|---|---|---|
| `_gacavali-1` | router-gacavali-1 | route reflector (RR) |
| `_gacavali-2` | router-gacavali-2 | leaf et VTEP |
| `_gacavali-3` | router-gacavali-3 | leaf et VTEP |
| `_gacavali-4` | router-gacavali-4 | leaf et VTEP |
| `_gacavali-1_host` | host-gacavali-1 | hôte derrière le routeur 2 |
| `_gacavali-2_host` | host-gacavali-2 | hôte derrière le routeur 3 |
| `_gacavali-3_host` | host-gacavali-3 | hôte derrière le routeur 4 |
| `P3.gns3project` | tous | export ZIP avec topologie et images Docker |

Comme en P2, chaque fichier est un script à coller dans la console de son
équipement. La configuration OSPF et BGP passe par `vtysh`. Elle est perdue
quand l’équipement s’arrête.

Chaque script de routeur suit le même plan :

| Couche | Ce qu’elle fait | Outil |
|---|---|---|
| 1. Transport | Adresses, loopback, OSPF aire 0 | `vtysh` |
| 2. Données | Bridge `br0` et tunnel `vxlan10` (leaves seulement) | `ip` |
| 3. Contrôle | Session BGP avec le RR, famille EVPN | `vtysh` |

## Vocabulaire

| Mot | Sens |
|---|---|
| OSPF | Le protocole qui apprend à chaque routeur le chemin vers les loopbacks des autres. |
| Loopback | Une adresse qui appartient au routeur et non à un câble (1.1.1.x). Elle reste joignable tant qu’un lien fonctionne. |
| BGP | Le protocole qui transporte les annonces entre routeurs. Ici il ne transporte pas des routes IP mais des adresses MAC. |
| AS | Le numéro du groupe de routeurs gérés ensemble. Ici 1 pour tous, comme dans le sujet : c’est donc de l’iBGP (BGP interne). |
| EVPN | La famille BGP qui annonce « telle adresse MAC est derrière tel VTEP ». |
| Route reflector (RR) | Le routeur central qui répète aux leaves ce que chaque leaf lui annonce. Sans lui, chaque leaf devrait parler à tous les autres. |
| Leaf | Un routeur de bord, celui où les hôtes sont branchés. |
| VTEP | L’extrémité d’un tunnel VXLAN. Ici, chaque leaf, avec sa loopback comme adresse. |
| VNI | L’identifiant du VXLAN, ici 10. |
| Route de type 3 | « Je suis un VTEP pour le VNI 10. » Annoncée dès que le leaf est configuré. |
| Route de type 2 | « Telle adresse MAC est chez moi. » Créée quand un hôte envoie sa première trame. |

Relations dynamiques : le RR ne liste pas ses leaves un par un. Il accepte
tout voisin dont l’adresse est dans `1.1.1.0/29` (`bgp listen range`).

## Restaurer et lancer

1. Charger les images Docker comme indiqué dans [P1/README.md](../P1/README.md).
2. Importer P3.gns3project dans GNS3 avec File → Import portable project.
3. Démarrer les quatre routeurs, puis coller dans la console de chacun le
   contenu de son fichier `_gacavali-N`.
4. Démarrer les hôtes un par un pour voir apparaître les routes de type 2.
5. Coller dans chaque hôte le contenu de son fichier `_gacavali-N_host`.

## Vérifications

Sur un leaf, dans `vtysh` :

```
show ip route
show bgp summary
show bgp l2vpn evpn
```

| Commande | Ce qu’on doit voir |
|---|---|
| `show ip route` | Les loopbacks 1.1.1.x des autres routeurs, apprises par OSPF (lettre `O`). |
| `show bgp summary` | Un seul voisin, le RR `1.1.1.1`, avec une durée dans la colonne Up/Down. |
| `show bgp l2vpn evpn` | Sans hôte : une route de type 3 par leaf. Avec un hôte démarré : une route de type 2 portant son adresse MAC, même sans adresse IP. |

### Durée de vie des routes de type 2

Un leaf garde une adresse MAC dans la table de `br0` pendant 300 secondes
après la dernière trame reçue (durée par défaut d’un bridge Linux). Tant
qu’elle y est, la route de type 2 reste annoncée, même si l’hôte est arrêté.

| Situation | Routes de type 2 |
|---|---|
| Les hôtes n’ont jamais été démarrés | Aucune |
| Hôtes démarrés puis arrêtés | Encore présentes, jusqu’à 5 minutes |
| Port de l’hôte éteint puis rallumé sur le leaf | Aucune après 2 secondes |

Pour retirer ces routes sans attendre, éteindre puis rallumer le port de
l’hôte dans le shell du leaf :

```sh
# router-gacavali-2
ip link set eth1 down
ip link set eth1 up

# router-gacavali-3 et router-gacavali-4
ip link set eth0 down
ip link set eth0 up
```

Depuis l’hôte 1, une fois les adresses posées :

```sh
ping -c 4 20.1.1.2
ping -c 4 20.1.1.3
```

Dans GNS3, une capture sur un lien entre le RR et un leaf montre les paquets
ICMP emballés dans du VXLAN de VNI 10, et les paquets Hello d’OSPF.
