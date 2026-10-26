#!/bin/bash
#
# Sauvegarde nocturne de la base, lancée par backup-db.timer (et au démarrage
# si la VM était éteinte à l'heure prévue). Les dumps vont dans ~/backups
# (dossier en 700, fichiers en 600) ; seuls les GARDER plus récents restent.
# Restauration : voir la section Exploitation du README.
#
set -euo pipefail
cd /home/debian/medical-office-db

DEST=/home/debian/backups
GARDER=7
umask 077
mkdir -p "$DEST"
chmod 700 "$DEST"

# Au démarrage, la base peut mettre quelques secondes à accepter les connexions
for i in $(seq 30); do
    docker compose exec -T db pg_isready -U postgres_admin -q && break
    sleep 2
done

# Écriture dans un fichier temporaire, renommé seulement si le dump a réussi :
# un dump interrompu ne peut pas être pris pour une sauvegarde valide.
FICHIER="$DEST/medical_office-$(date +%F_%H%M).sql.gz"
trap 'rm -f "$FICHIER.partiel"' EXIT
docker compose exec -T db pg_dump -U postgres_admin medical_office | gzip > "$FICHIER.partiel"
gzip -t "$FICHIER.partiel"
mv "$FICHIER.partiel" "$FICHIER"
chown debian:debian "$DEST" "$FICHIER"

# Rotation : on ne garde que les GARDER dumps les plus récents
ls -1t "$DEST"/medical_office-*.sql.gz | tail -n +$((GARDER + 1)) | xargs -r rm --

echo "Sauvegarde : $FICHIER ($(du -h "$FICHIER" | cut -f1)), $(ls -1 "$DEST"/medical_office-*.sql.gz | wc -l) dumps conservés"
