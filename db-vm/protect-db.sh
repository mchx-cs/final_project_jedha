#!/bin/bash
#
# Remplace la version précédente : le port 5432 n'est joignable que depuis
# le serveur web (dossiers patients) ET la VM DMZ (prise de rendez-vous).
# À rejouer après chaque redémarrage de la VM base.
#
set -euo pipefail

WEB="192.168.50.3"
DMZ="192.168.60.2"
IFACE="ens4"

add_rule() {   # insère en tête, sans doublon
    sudo iptables -C "$@" 2>/dev/null || sudo iptables -I "$@"
}

# L'ordre compte : le refus est posé en premier, les autorisations passent
# devant lui au fur et à mesure des insertions en tête de chaîne.
add_rule DOCKER-USER -i "$IFACE" -p tcp --dport 5432 -j DROP
add_rule DOCKER-USER -i "$IFACE" -p tcp --dport 5432 -s "$WEB" -j RETURN
add_rule DOCKER-USER -i "$IFACE" -p tcp --dport 5432 -s "$DMZ" -j RETURN

sudo iptables -L DOCKER-USER -n --line-numbers
