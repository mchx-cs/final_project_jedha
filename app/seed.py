"""
Crée les comptes du personnel initiaux.
Ne fait rien de magique : hash bcrypt côté Python (même lib que l'appli, donc
pas de souci de compatibilité de format), puis INSERT paramétré.

Usage (une fois les conteneurs lancés) :
    docker compose exec app python seed.py
"""
import os
import sys

import bcrypt
import psycopg2

DB_CONFIG = dict(
    host=os.environ.get("DB_HOST", "db"),
    port=os.environ.get("DB_PORT", "5432"),
    dbname=os.environ["DB_NAME"],
    user=os.environ["DB_USER"],
    password=os.environ["DB_PASSWORD"],
)


def create_account(username, password, role, full_name):
    password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=12)).decode("utf-8")
    conn = psycopg2.connect(**DB_CONFIG)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO staff (username, password_hash, role, full_name)
                   VALUES (%s, %s, %s, %s)
                   ON CONFLICT (username) DO NOTHING""",
                (username, password_hash, role, full_name),
            )
        conn.commit()
    finally:
        conn.close()
    print(f"Compte '{username}' ({role}) prêt.")


if __name__ == "__main__":
    admin_user = os.environ.get("SEED_ADMIN_USER", "dr.martin")
    admin_password = os.environ.get("SEED_ADMIN_PASSWORD")
    secretary_user = os.environ.get("SEED_SECRETARY_USER", "secretariat")
    secretary_password = os.environ.get("SEED_SECRETARY_PASSWORD")

    if not admin_password or not secretary_password:
        sys.exit(
            "SEED_ADMIN_PASSWORD et SEED_SECRETARY_PASSWORD doivent être définis dans .env "
            "avant de lancer ce script (pas de mot de passe par défaut en dur)."
        )

    create_account(admin_user, admin_password, "medecin", "Dr Martin")
    create_account(secretary_user, secretary_password, "secretaire", "Secrétariat")
