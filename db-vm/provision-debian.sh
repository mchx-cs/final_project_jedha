#!/bin/bash
#
# Provisionne un nœud Debian 12 fraîchement déployé dans GNS3 :
# nom d'hôte, clés SSH d'hôte, adresse fixe liée à la MAC, DNS,
# neutralisation de cloud-init, Docker.
#
# ---------------------------------------------------------------------------
# AVANT DE LANCER CE SCRIPT
#
# 1. Agrandir le disque du nœud, depuis la VM GNS3, nœud ÉTEINT :
#       find /opt/gns3/projects -name "hda_disk.qcow2"
#       qemu-img resize <le chemin du bon nœud> +18G
#
# 2. Faire réserver l'adresse du nœud dans pfSense (DHCP, par adresse MAC),
#    et ouvrir temporairement l'accès Internet de son VLAN : le script
#    installe Docker depuis download.docker.com. Refermer cet accès ensuite.
#
# 3. Démarrer le nœud, ouvrir sa console GNS3 et récupérer une adresse :
#       sudo dhclient -v ens4
#    La sortie indique l'adresse réservée, la passerelle et les DNS.
#
# 4. Copier ce script sur le nœud (collage dans la console avec
#    cat > provision-debian.sh <<'SCRIPT' ... SCRIPT), puis :
#       chmod +x provision-debian.sh
#       sudo ./provision-debian.sh 192.168.50.2 db-medical 192.168.50.1 192.168.40.2,8.8.8.8
#
# Paramètres : adresse, nom d'hôte, passerelle, DNS séparés par des virgules
# (8.8.8.8 par défaut), interface (ens4 par défaut). Masque : /24.
# ---------------------------------------------------------------------------

set -euo pipefail

USAGE="Usage: $0 <ip> <nom-d-hote> <passerelle> [dns1,dns2] [interface]"
IP="${1:?$USAGE}"
HOSTNAME_NEW="${2:?$USAGE}"
GATEWAY="${3:?$USAGE}"
DNS_LIST="${4:-8.8.8.8}"
IFACE="${5:-ens4}"
MASK=24

[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo." >&2; exit 1; }
MAC="$(cat "/sys/class/net/${IFACE}/address" 2>/dev/null)" \
    || { echo "Interface ${IFACE} introuvable." >&2; exit 1; }

echo "== 1/7 Nom d'hôte : ${HOSTNAME_NEW}"
hostnamectl set-hostname "$HOSTNAME_NEW"
sed -i "s/^127.0.1.1.*/127.0.1.1\t${HOSTNAME_NEW}/" /etc/hosts || true

echo "== 2/7 Clés SSH d'hôte"
# Une VM issue du template GNS3 partage ses clés d'hôte avec toutes les
# autres : on les régénère pour qu'aucune machine ne puisse en usurper une autre.
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A
systemctl restart ssh

echo "== 3/7 Neutralisation de cloud-init (réseau et nom d'hôte)"
echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
echo 'preserve_hostname: true'     > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg

echo "== 4/7 Adresse fixe : ${IP}/${MASK} sur ${IFACE} (${MAC}), passerelle ${GATEWAY}"
# La configuration est liée à la MAC : un clone du nœud, qui aura une autre
# MAC, ne prendra pas cette adresse.
cat > "/etc/systemd/network/10-${IFACE}.network" <<CONF
[Match]
MACAddress=${MAC}

[Network]
Address=${IP}/${MASK}
Gateway=${GATEWAY}
CONF
dhclient -r "$IFACE" 2>/dev/null || true
pkill dhclient 2>/dev/null || true
ip addr flush dev "$IFACE"
systemctl enable systemd-networkd >/dev/null 2>&1 || true
systemctl restart systemd-networkd
sleep 3

echo "== 5/7 Résolution DNS : ${DNS_LIST}"
# Le lien d'origine pointe vers /run, vidé à chaque démarrage :
# on le remplace par un vrai fichier.
rm -f /etc/resolv.conf
for dns in ${DNS_LIST//,/ }; do
    echo "nameserver ${dns}"
done > /etc/resolv.conf

echo "== 6/7 Accès aux dépôts de paquets"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || {
    echo "Dépôts injoignables : l'accès Internet du VLAN est-il ouvert dans pfSense ?" >&2
    exit 1
}

echo "== 7/7 Docker (dépôt officiel)"
apt-get install -y -qq ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker debian

cat <<FIN

-------------------------------------------------------------------
Terminé. Hôte ${HOSTNAME_NEW}, adresse ${IP}/${MASK} sur ${IFACE}.

Déconnecte-toi puis reconnecte-toi (pour que le groupe docker prenne
effet), puis vérifie :

    ip -br a; ip route; cat /etc/resolv.conf
    docker run --rm hello-world

Pense à faire refermer l'accès Internet du VLAN dans pfSense.
-------------------------------------------------------------------
FIN
