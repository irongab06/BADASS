# BADASS — P2

Deux hôtes, chacun derrière son routeur, se parlent comme s’ils étaient
branchés sur le même switch. Le lien entre les deux routeurs est un tunnel
VXLAN d’identifiant 10, d’abord en mode statique, puis en mode multicast.

## Topologie

```
                      10.1.1.0/24 (transport)
                 eth0 ┌───────────────┐ eth0
        ┌─────────────┤switch-gacavali├─────────────┐
        │ 10.1.1.1    └───────────────┘    10.1.1.2 │
┌───────┴─────────┐                       ┌─────────┴───────┐
│router-gacavali-1│                       │router-gacavali-2│
│  br0 + vxlan10  │                       │  br0 + vxlan10  │
└───────┬─────────┘                       └─────────┬───────┘
        │ eth1                                 eth1 │
        │ eth1                                 eth1 │
┌───────┴─────────┐                       ┌─────────┴───────┐
│ host-gacavali-1 │                       │ host-gacavali-2 │
│   30.1.1.1/24   │                       │   30.1.1.2/24   │
└─────────────────┘                       └─────────────────┘
```

## Contenu

Chaque fichier est le `/etc/network/interfaces` d’un équipement.

| Fichier | Équipement | Mode |
|---|---|---|
| `_gacavali-1_host` | host-gacavali-1 | les deux |
| `_gacavali-2_host` | host-gacavali-2 | les deux |
| `_gacavali-1_s` | router-gacavali-1 | statique |
| `_gacavali-2_s` | router-gacavali-2 | statique |
| `_gacavali-1_g` | router-gacavali-1 | multicast (groupe) |
| `_gacavali-2_g` | router-gacavali-2 | multicast (groupe) |
| `P2.gns3project` | tous | export ZIP avec topologie et images Docker |

Le projet exporté démarre en mode statique : les fichiers `_s` et `_host`
sont déjà en place dans les équipements.

## Vocabulaire

| Mot | Sens |
|---|---|
| Underlay | Le réseau de transport entre les routeurs (10.1.1.0/24). |
| Overlay | Le réseau virtuel vu par les hôtes (30.1.1.0/24). |
| VXLAN | Un tunnel qui range une trame Ethernet entière dans un paquet UDP (port 4789). |
| VNI | L’identifiant du VXLAN, ici 10. Il doit être le même aux deux bouts. |
| VTEP | L’équipement qui ouvre et ferme le tunnel. Ici, chaque routeur. |
| Bridge | Un switch logiciel dans le routeur (`br0`). Il relie `eth1` et `vxlan10`. |
| Multicast | Un paquet envoyé à un groupe de machines (239.1.1.1) au lieu d’une seule. |

Trajet d’un paquet : l’hôte 1 envoie une trame, `br0` du routeur 1 la passe
à `vxlan10`, qui l’emballe dans un paquet UDP vers le routeur 2. Le routeur 2
la déballe et son `br0` la remet à l’hôte 2.

Différence entre les deux modes :

| Mode | Comment le routeur 1 trouve le routeur 2 |
|---|---|
| Statique | Son adresse est écrite à la main : `remote 10.1.1.2`. |
| Multicast | Les deux routeurs rejoignent le groupe `239.1.1.1` et s’y découvrent. |

## Restaurer

Charger les images Docker comme indiqué dans [P1/README.md](../P1/README.md),
puis importer P2.gns3project dans GNS3 avec
File → Import portable project.

## Passer du statique au multicast

Sur chaque routeur, clic droit → Edit config, remplacer le contenu par celui
du fichier `_g` du routeur, puis arrêter et redémarrer le routeur.

Pour un essai rapide sans redémarrage, dans la console du routeur 1 :

```sh
/sbin/ip link del vxlan10
/sbin/ip link add vxlan10 type vxlan id 10 local 10.1.1.1 group 239.1.1.1 dev eth0 dstport 4789
/sbin/ip link set vxlan10 master br0
/sbin/ip link set vxlan10 up
```

Même chose sur le routeur 2 avec `local 10.1.1.2`. Ce changement est perdu
au redémarrage : le routeur relit son fichier de configuration.

## Vérifications

Depuis l’hôte 1 :

```sh
ping -c 4 30.1.1.2
```

Sur chaque routeur :

```sh
/sbin/ip -d link show vxlan10
bridge fdb show br br0
```

La première commande affiche `vxlan id 10`, puis `remote 10.1.1.x` en
statique ou `group 239.1.1.1` en multicast. La seconde affiche la table des
adresses MAC : l’hôte local sur `eth1`, l’hôte distant sur `vxlan10`.

Dans GNS3, une capture sur le lien entre un routeur et le switch montre des
paquets UDP sur le port 4789, avec le VNI 10.
