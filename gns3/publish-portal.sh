#!/bin/bash
#
# Publication du site public de prise de rendez-vous sur le réseau du lab.
#
#   lab -> 192.168.183.147:8444 (VM GNS3) -> 192.168.122.86:443 (WAN pfSense)
#       -> redirection pfSense -> 192.168.60.2:443 (dmz-rdv)
#
# Le portail du personnel n'est plus publié : il n'est joignable que depuis
# les VLAN du personnel. Script idempotent, relancé au démarrage par
# publish-portal.service.
#
set -euo pipefail

PUB_IP="192.168.183.147"   # adresse de la VM GNS3 sur le réseau du lab
PUB_PORT="8444"
WAN_IP="192.168.122.86"    # interface WAN de pfSense

# Redirection : ajoutée une seule fois
iptables -t nat -C PREROUTING -d "$PUB_IP" -p tcp --dport "$PUB_PORT" \
         -j DNAT --to-destination "$WAN_IP:443" 2>/dev/null \
  || iptables -t nat -A PREROUTING -d "$PUB_IP" -p tcp --dport "$PUB_PORT" \
         -j DNAT --to-destination "$WAN_IP:443"

# Autorisation : insérée en tête, avant les règles de libvirt qui refusent
# les connexions entrantes vers virbr0
iptables -C FORWARD -d "$WAN_IP" -p tcp --dport 443 -j ACCEPT 2>/dev/null \
  || iptables -I FORWARD -d "$WAN_IP" -p tcp --dport 443 -j ACCEPT

iptables -t nat -S PREROUTING | grep -- "--dport $PUB_PORT"
iptables -S FORWARD | grep -- "-d $WAN_IP"
