#!/bin/bash
# Restreint le 5432 au seul serveur web. À rejouer après un redémarrage de la VM.
RULE="DOCKER-USER -i ens4 ! -s 192.168.122.50 -p tcp --dport 5432 -j DROP"
sudo iptables -C $RULE 2>/dev/null || sudo iptables -I $RULE
sudo iptables -L DOCKER-USER -n --line-numbers
