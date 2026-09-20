#!/bin/bash
# Exécuté automatiquement par l'image officielle postgres au premier démarrage
# (dossier /docker-entrypoint-initdb.d/). $POSTGRES_USER / $POSTGRES_DB / $APP_DB_PASSWORD
# viennent des variables d'environnement du conteneur (voir docker-compose.yml + .env).
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
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

    -- Compte applicatif à privilèges limités : ni superuser, ni droit de créer/supprimer des
    -- tables. C'est LUI que l'app Flask utilise (DB_USER), jamais le compte d'init POSTGRES_USER.
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

echo "Schéma initialisé + rôle app_user créé avec des droits limités."
