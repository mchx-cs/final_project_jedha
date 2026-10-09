#!/bin/bash
#
# Délai croissant après des échecs de connexion au portail : table des
# tentatives échouées, par identifiant. Utilisée par app.py (portail).
#
set -euo pipefail
cd "$(dirname "$0")"
set -a; . ./.env; set +a
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$DB_SUPERUSER" -d "$DB_NAME" <<'EOSQL'
CREATE TABLE IF NOT EXISTS login_attempts (
    username     VARCHAR(64) PRIMARY KEY,
    failures     INTEGER     NOT NULL DEFAULT 0,
    last_failure TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON login_attempts TO app_user;
EOSQL
echo "Table login_attempts en place, accessible au rôle app_user."
