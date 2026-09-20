#!/bin/bash
# Exécuté une seule fois, au premier démarrage du conteneur postgres.
# Crée le schéma, le rôle applicatif à privilèges limités, puis restreint
# les connexions réseau au seul serveur web.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS staff (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(64) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role          VARCHAR(20) NOT NULL CHECK (role IN ('medecin', 'secretaire')),
    full_name     VARCHAR(150) NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS patients (
    id             SERIAL PRIMARY KEY,
    first_name     VARCHAR(100) NOT NULL,
    last_name      VARCHAR(100) NOT NULL,
    date_of_birth  DATE NOT NULL,
    notes          TEXT,
    created_by     INTEGER REFERENCES staff(id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD '${APP_DB_PASSWORD}';
    END IF;
END
\$\$;

GRANT CONNECT ON DATABASE "$POSTGRES_DB" TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON staff, patients TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
EOSQL

# Contrôle d'accès réseau au niveau de PostgreSQL lui-même : seul le rôle
# app_user, depuis l'adresse du serveur web, sur cette base précise.
# Le compte superuser devient injoignable par le réseau.
cat > "$PGDATA/pg_hba.conf" <<EOF
# TYPE  DATABASE            USER        ADDRESS                     METHOD
local   all                 all                                     trust
host    all                 all         127.0.0.1/32                scram-sha-256
host    all                 all         ::1/128                     scram-sha-256
host    ${POSTGRES_DB}      app_user    ${APP_ALLOWED_CIDR}         scram-sha-256
EOF

echo "Schéma créé, rôle app_user restreint, pg_hba.conf limité à ${APP_ALLOWED_CIDR}"
