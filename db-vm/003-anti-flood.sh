#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
set -a; . ./.env; set +a
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$DB_SUPERUSER" -d "$DB_NAME" <<'EOSQL'
CREATE INDEX IF NOT EXISTS appointments_phone_pending_idx
    ON appointments (regexp_replace(phone, '\D', '', 'g')) WHERE status = 'demande';

CREATE OR REPLACE FUNCTION appointments_anti_flood() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF (SELECT count(*) FROM appointments
        WHERE status = 'demande'
          AND regexp_replace(phone, '\D', '', 'g') = regexp_replace(NEW.phone, '\D', '', 'g')) >= 3 THEN
        RAISE EXCEPTION 'trop de demandes en attente pour ce numero';
    END IF;
    IF (SELECT count(*) FROM appointments WHERE status = 'demande') >= 500 THEN
        RAISE EXCEPTION 'file de demandes saturee';
    END IF;
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION appointments_anti_flood() FROM PUBLIC;

DROP TRIGGER IF EXISTS appointments_anti_flood ON appointments;
CREATE TRIGGER appointments_anti_flood BEFORE INSERT ON appointments
    FOR EACH ROW EXECUTE FUNCTION appointments_anti_flood();
EOSQL
echo "Trigger anti-flood en place : 3 demandes en attente par numéro, 500 au total."
