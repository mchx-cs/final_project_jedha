"""
Crée les comptes du personnel initiaux.

Les mots de passe ne sont jamais stockés dans .env ni dans l'environnement du
conteneur : ils sont demandés à l'écran, saisie masquée, uniquement pour les
comptes qui n'existent pas encore. Un compte existant n'est jamais modifié.

Usage (une fois les conteneurs lancés) :
    sudo docker compose exec app python seed.py
"""
import getpass
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

COMPTES = [
    ("dr.martin", "medecin", "Dr Martin"),
    ("secretariat", "secretaire", "Secrétariat"),
]
LONGUEUR_MIN = 12


def demander_mot_de_passe(username):
    for _ in range(3):
        p1 = getpass.getpass(f"Mot de passe de {username} : ")
        p2 = getpass.getpass("Encore une fois : ")
        if p1 != p2:
            print("Les deux saisies diffèrent.")
        elif len(p1) < LONGUEUR_MIN:
            print(f"Au moins {LONGUEUR_MIN} caractères.")
        else:
            return p1
    sys.exit(f"Abandon : aucun compte créé pour {username}.")


def main():
    conn = psycopg2.connect(**DB_CONFIG)
    try:
        for username, role, full_name in COMPTES:
            with conn.cursor() as cur:
                cur.execute("SELECT 1 FROM staff WHERE username = %s", (username,))
                if cur.fetchone():
                    print(f"Compte '{username}' déjà présent : inchangé.")
                    continue
                password = demander_mot_de_passe(username)
                password_hash = bcrypt.hashpw(password.encode("utf-8"),
                                              bcrypt.gensalt(rounds=12)).decode("utf-8")
                cur.execute(
                    """INSERT INTO staff (username, password_hash, role, full_name)
                       VALUES (%s, %s, %s, %s)
                       ON CONFLICT (username) DO NOTHING""",
                    (username, password_hash, role, full_name),
                )
            conn.commit()
            print(f"Compte '{username}' ({role}) créé.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
