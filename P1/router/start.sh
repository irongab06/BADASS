#!/bin/sh
set -e

# Demarrer FRRouting avec les services actives dans /etc/frr/daemons.
/usr/lib/frr/frrinit.sh start

# Remplacer ce script par un shell interactif.
exec /bin/sh
