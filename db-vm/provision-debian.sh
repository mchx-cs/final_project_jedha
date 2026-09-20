#!/bin/bash
#
# Provisionne un nœud Debian 12 fraîchement déployé dans GNS3 :
# nom d'hôte, IP statique persistante, DNS, neutralisation de cloud-init, Docker.
#
# ---------------------------------------------------------------------------
# AVANT DE LANCER CE SCRIPT
#
# 1. Agrandir le disque du nœud, depuis la VM GNS3, nœud ÉTEINT :
#       find /opt/gns3/projects -name "hda_disk.qcow2"
#       qemu-img resize <le chemin du bon nœud> +18G
#
# 2. Démarrer le nœud et ouvrir sa console (telnet). L'interface est éteinte,
#    donc il faut la monter à la main le temps de récupérer ce script :
#       sudo ip link set ens4 up
#       sudo ip addr add 192.168.122.51/24 dev ens4
#       sudo ip route add default via 192.168.122.1
#
# 3. Envoyer ce script depuis ton PC :
#       scp -J gns3@192.168.183.147 provision-debian.sh debian@192.168.122.51:~/
#
# 4. Puis, sur le nœud :
#       chmod +x provision-debian.sh
#       sudo ./provision-debian.sh 192.168.122.51 db-medical
#
# L'adresse passée en argument doit être celle que tu viens de configurer
# temporairement : le script la rend permanente sans couper ta session.
# ---------------------------------------------------------------------------

set -euo pipefail

IP="${1:?Usage: $0 <ip-sans-masque> <nom-d-hote> [interface]}"
HOSTNAME_NEW="${2:?Usage: $0 <ip-sans-masque> <nom-d-hote> [interface]}"
IFACE="${3:-ens4}"
GATEWAY="192.168.122.1"

[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo." >&2; exit 1; }

echo "== 1/6 Nom d'hôte : ${HOSTNAME_NEW}"
hostnamectl set-hostname "$HOSTNAME_NEW"
sed -i "s/^127.0.1.1.*/127.0.1.1\t${HOSTNAME_NEW}/" /etc/hosts || true

echo "== 2/6 Clés SSH d'hôte"
# Utile si la VM a été dupliquée : deux machines ne doivent jamais partager
# leurs clés d'hôte. Sur une VM neuve, cette étape est simplement sans effet.
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A
systemctl restart ssh

echo "== 3/6 Adresse IP statique : ${IP}/24 sur ${IFACE}"
cat > "/etc/systemd/network/10-${IFACE}.network" <<EOF
[Match]
Name=${IFACE}

[Network]
Address=${IP}/24
Gateway=${GATEWAY}
DNS=${GATEWAY}
DNS=8.8.8.8
EOF
systemctl enable --now systemd-networkd >/dev/null 2>&1 || true
systemctl restart systemd-networkd

echo "== 4/6 Neutralisation de la configuration réseau de cloud-init"
echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

echo "== 5/6 Résolution DNS"
# Le lien symbolique d'origine pointe vers /run, vidé à chaque démarrage :
# on le remplace par un vrai fichier.
rm -f /etc/resolv.conf
printf 'nameserver %s\nnameserver 8.8.8.8\n' "$GATEWAY" > /etc/resolv.conf

echo "   Attente de la connectivité..."
for _ in $(seq 1 20); do
    ping -c1 -W1 deb.debian.org >/dev/null 2>&1 && break
    sleep 2
done
ping -c1 -W2 deb.debian.org >/dev/null 2>&1 || {
    echo "Pas de connectivité vers Internet. Vérifie le lien vers le NAT dans GNS3." >&2
    exit 1
}

echo "== 6/6 Docker (dépôt officiel)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg unzip
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker debian

cat <<EOF

-------------------------------------------------------------------
Terminé. Hôte ${HOSTNAME_NEW}, adresse ${IP}/24 sur ${IFACE}.

Reconnecte-toi (pour que le groupe docker prenne effet), puis vérifie :

    ip -br a
    docker run --rm hello-world

Les clés SSH d'hôte ayant changé, ton client refusera peut-être la
connexion. Dans ce cas, sur ton PC :

    ssh-keygen -R ${IP}
-------------------------------------------------------------------
EOF
