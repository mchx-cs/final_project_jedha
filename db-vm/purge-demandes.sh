#!/bin/bash
#
# Purge des demandes de rendez-vous de plus de six mois : durée de conservation
# annoncée aux patients sur le site public. Lancé chaque nuit par
# purge-demandes.timer, et au démarrage si la VM était éteinte à l'heure prévue.
#
set -euo pipefail
cd /home/debian/medical-office-db

# Au démarrage, la base peut mettre quelques secondes à accepter les connexions
for i in $(seq 30); do
    docker compose exec -T db pg_isready -U postgres_admin -q && break
    sleep 2
done

docker compose exec -T db psql -U postgres_admin -d medical_office -v ON_ERROR_STOP=1 \
    -c "DELETE FROM appointments WHERE created_at < now() - interval '6 months';"
