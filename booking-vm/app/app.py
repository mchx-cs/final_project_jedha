"""
Prise de rendez-vous — application publique.

Volontairement minimale : elle ne fait qu'enregistrer une demande de contact.
Elle ne lit rien, ne gère aucun compte patient, et ne connaît aucune donnée
médicale. Son rôle PostgreSQL ne dispose que du droit INSERT sur une table.
"""
import os
import re
import logging
import uuid
from datetime import date, timedelta

from flask import Flask, render_template, request
from flask_wtf import FlaskForm, CSRFProtect
from wtforms import StringField, SelectField, DateField, TextAreaField
from wtforms.validators import DataRequired, Length, Optional, Email, Regexp, ValidationError
import psycopg2

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("booking")

app = Flask(__name__)
app.config["SECRET_KEY"] = os.environ["FLASK_SECRET_KEY"]
app.config["SESSION_COOKIE_SECURE"] = True
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024

csrf = CSRFProtect(app)

DB_CONFIG = dict(
    host=os.environ["DB_HOST"],
    port=os.environ.get("DB_PORT", "5432"),
    dbname=os.environ["DB_NAME"],
    user=os.environ["DB_USER"],          # booking_user : INSERT seul
    password=os.environ["DB_PASSWORD"],
    connect_timeout=5,
)

HORIZON_JOURS = 90


class DemandeForm(FlaskForm):
    last_name = StringField("Nom", validators=[DataRequired(), Length(min=2, max=100)])
    first_name = StringField("Prénom", validators=[DataRequired(), Length(min=2, max=100)])
    phone = StringField(
        "Téléphone",
        validators=[DataRequired(), Length(min=10, max=30),
                    Regexp(r"^[0-9 +().-]+$", message="Chiffres et séparateurs uniquement.")],
    )
    email = StringField("Adresse e-mail (facultatif)",
                        validators=[Optional(), Email(), Length(max=150)])
    requested_date = DateField("Date souhaitée", validators=[DataRequired()])
    slot = SelectField("Moment de la journée",
                       choices=[("matin", "Matin"), ("apres-midi", "Après-midi")],
                       validators=[DataRequired()])
    comment = TextAreaField("Précisions pratiques (facultatif)",
                            validators=[Optional(), Length(max=200)])
    # Champ piège : invisible pour un humain, rempli par la plupart des robots.
    website = StringField("Ne pas remplir")

    def validate_requested_date(self, field):
        if field.data < date.today():
            raise ValidationError("La date ne peut pas être dans le passé.")
        if field.data > date.today() + timedelta(days=HORIZON_JOURS):
            raise ValidationError(f"Les demandes sont ouvertes sur {HORIZON_JOURS} jours.")


def enregistrer(form):
    """Insère la demande et renvoie la référence communiquée au patient.

    La référence est générée ici, pas par la base : le rôle applicatif n'a
    aucun droit de lecture, il ne peut donc pas utiliser RETURNING.
    """
    for _ in range(3):
        reference = uuid.uuid4().hex[:8].upper()
        conn = psycopg2.connect(**DB_CONFIG)
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """INSERT INTO appointments
                       (reference, last_name, first_name, phone, email,
                        requested_date, slot, comment)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
                    (reference, form.last_name.data.strip(), form.first_name.data.strip(),
                     form.phone.data.strip(), (form.email.data or "").strip() or None,
                     form.requested_date.data, form.slot.data,
                     (form.comment.data or "").strip() or None),
                )
            conn.commit()
            return reference
        except psycopg2.errors.UniqueViolation:
            conn.rollback()
            continue
        finally:
            conn.close()
    raise RuntimeError("Impossible de générer une référence unique")


@app.route("/", methods=["GET", "POST"])
def demande():
    form = DemandeForm()
    if form.validate_on_submit():
        if form.website.data:
            # Robot : on répond comme si tout allait bien, sans rien enregistrer.
            logger.warning("honeypot_triggered ip=%s", request.remote_addr)
            return render_template("confirmation.html", reference="—")
        try:
            reference = enregistrer(form)
        except Exception:
            logger.exception("booking_failed ip=%s", request.remote_addr)
            return render_template("form.html", form=form,
                                   erreur="Le service est momentanément indisponible. "
                                          "Merci de contacter le cabinet par téléphone."), 503
        logger.info("booking_created reference=%s ip=%s", reference, request.remote_addr)
        return render_template("confirmation.html", reference=reference)
    return render_template("form.html", form=form)


@app.route("/sante")
def sante():
    return {"statut": "ok"}, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
