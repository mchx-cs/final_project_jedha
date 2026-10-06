#!/bin/bash
#
# À lancer SUR LA VM BASE (192.168.50.2), depuis ~/medical-office-db.
#
# Crée la table des demandes de rendez-vous, le rôle applicatif public
# `booking_user` — qui ne peut QU'INSÉRER dans cette table, rien lire — et
# autorise sa connexion depuis la seule VM DMZ.
#
# Avant de lancer, ajoute deux lignes dans le .env de cette VM :
#   BOOKING_DB_PASSWORD=<mot de passe fort généré avec openssl rand -base64 24>
#   BOOKING_ALLOWED_CIDR=192.168.60.2/32
#
set -euo pipefail
cd "$(dirname "$0")"

set -a; . ./.env; set +a
: "${BOOKING_DB_PASSWORD:?Ajoute BOOKING_DB_PASSWORD=... dans .env}"
: "${BOOKING_ALLOWED_CIDR:?Ajoute BOOKING_ALLOWED_CIDR=192.168.60.2/32 dans .env}"

docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$DB_SUPERUSER" -d "$DB_NAME" <<EOSQL
CREATE TABLE IF NOT EXISTS appointments (
    id             SERIAL PRIMARY KEY,
    reference      VARCHAR(12) UNIQUE NOT NULL,
    last_name      VARCHAR(100) NOT NULL,
    first_name     VARCHAR(100) NOT NULL,
    phone          VARCHAR(30)  NOT NULL,
    email          VARCHAR(150),
    requested_date DATE NOT NULL,
    slot           VARCHAR(20) NOT NULL CHECK (slot IN ('matin', 'apres-midi')),
    comment        VARCHAR(200),
    status         VARCHAR(20) NOT NULL DEFAULT 'demande'
                   CHECK (status IN ('demande', 'confirme', 'refuse')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    handled_by     INTEGER REFERENCES staff(id),
    handled_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS appointments_status_idx ON appointments (status, requested_date);

DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'booking_user') THEN
        CREATE ROLE booking_user LOGIN PASSWORD '${BOOKING_DB_PASSWORD}';
    END IF;
END
\$\$;

-- Rôle public : écriture seule, sur une seule table.
-- Pas de SELECT : même compromise, l'application publique ne peut pas relire
-- les demandes des autres patients.
GRANT CONNECT ON DATABASE "$DB_NAME" TO booking_user;
GRANT INSERT ON appointments TO booking_user;
GRANT USAGE ON SEQUENCE appointments_id_seq TO booking_user;

-- Le portail du personnel lit et traite les demandes.
GRANT SELECT, UPDATE ON appointments TO app_user;
GRANT USAGE, SELECT ON SEQUENCE appointments_id_seq TO app_user;
EOSQL

# Autorisation réseau de booking_user depuis la seule VM DMZ.
docker compose exec -T db sh -c \
  "grep -q booking_user /var/lib/postgresql/data/pg_hba.conf || \
   echo 'host    ${DB_NAME}    booking_user    ${BOOKING_ALLOWED_CIDR}    scram-sha-256' \
   >> /var/lib/postgresql/data/pg_hba.conf"

docker compose exec -T db psql -U "$DB_SUPERUSER" -d "$DB_NAME" -c "SELECT pg_reload_conf();" > /dev/null

echo "Table appointments créée."
echo "Rôle booking_user : INSERT seul, autorisé depuis ${BOOKING_ALLOWED_CIDR}."
docker compose exec -T db cat /var/lib/postgresql/data/pg_hba.conf
