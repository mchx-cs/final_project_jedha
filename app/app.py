import os
import logging
from functools import wraps

from flask import Flask, render_template, request, redirect, url_for, session, flash, abort
from flask_wtf import FlaskForm, CSRFProtect
from wtforms import StringField, PasswordField, DateField, TextAreaField
from wtforms.validators import DataRequired, Length
import bcrypt
import psycopg2
import psycopg2.extras

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("medical-office")
# Ces logs partent sur stdout : c'est ce que Wazuh ira lire une fois la brique
# monitoring branchée dessus.

app = Flask(__name__)

# Pas de valeur par défaut sur le secret : l'appli refuse de démarrer si .env est mal rempli
app.config["SECRET_KEY"] = os.environ["FLASK_SECRET_KEY"]
app.config["SESSION_COOKIE_SECURE"] = True     # cookie envoyé uniquement en HTTPS
app.config["SESSION_COOKIE_HTTPONLY"] = True   # inaccessible en JS (protection XSS partielle)
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"  # limite le CSRF côté cookie

csrf = CSRFProtect(app)  # protège tous les formulaires POST (flask-wtf)

DB_CONFIG = dict(
    host=os.environ.get("DB_HOST", "db"),
    port=os.environ.get("DB_PORT", "5432"),
    dbname=os.environ["DB_NAME"],
    user=os.environ["DB_USER"],       # app_user : compte à privilèges limités
    password=os.environ["DB_PASSWORD"],
)


def get_db():
    return psycopg2.connect(**DB_CONFIG)


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if "user_id" not in session:
            return redirect(url_for("login", next=request.path))
        return view(*args, **kwargs)
    return wrapped


def role_required(*roles):
    def decorator(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if session.get("role") not in roles:
                abort(403)
            return view(*args, **kwargs)
        return wrapped
    return decorator


class LoginForm(FlaskForm):
    username = StringField("Identifiant", validators=[DataRequired(), Length(max=64)])
    password = PasswordField("Mot de passe", validators=[DataRequired()])


class PatientForm(FlaskForm):
    first_name = StringField("Prénom", validators=[DataRequired(), Length(max=100)])
    last_name = StringField("Nom", validators=[DataRequired(), Length(max=100)])
    date_of_birth = DateField("Date de naissance", validators=[DataRequired()])
    notes = TextAreaField("Notes médicales", validators=[Length(max=2000)])


@app.route("/")
def index():
    return redirect(url_for("dashboard") if "user_id" in session else url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    form = LoginForm()
    if form.validate_on_submit():
        username = form.username.data.strip()
        password = form.password.data.encode("utf-8")

        conn = get_db()
        try:
            with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
                # Requête paramétrée (%s) : jamais de f-string ni de concaténation
                # avec l'entrée utilisateur -> protection contre l'injection SQL.
                cur.execute(
                    "SELECT id, password_hash, role, full_name FROM staff WHERE username = %s",
                    (username,),
                )
                row = cur.fetchone()
        finally:
            conn.close()

        if row and bcrypt.checkpw(password, row["password_hash"].encode("utf-8")):
            session.clear()
            session["user_id"] = row["id"]
            session["role"] = row["role"]
            session["full_name"] = row["full_name"]
            logger.info("auth_success user=%s ip=%s", username, request.remote_addr)
            return redirect(url_for("dashboard"))

        # Message générique : on ne dit pas si c'est le login ou le mot de passe qui est faux
        logger.warning("auth_failure user=%s ip=%s", username, request.remote_addr)
        flash("Identifiants invalides", "error")

    return render_template("login.html", form=form)


@app.route("/logout")
def logout():
    logger.info("logout user=%s", session.get("full_name"))
    session.clear()
    return redirect(url_for("login"))


@app.route("/dashboard")
@login_required
def dashboard():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM appointments WHERE status = 'demande'")
            en_attente = cur.fetchone()[0]
    finally:
        conn.close()
    return render_template("dashboard.html", en_attente=en_attente)


@app.route("/patients")
@login_required
def patients_list():
    conn = get_db()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
            cur.execute(
                "SELECT id, first_name, last_name, date_of_birth FROM patients ORDER BY last_name"
            )
            patients = cur.fetchall()
    finally:
        conn.close()
    return render_template("patients.html", patients=patients)


@app.route("/patients/new", methods=["GET", "POST"])
@login_required
def patients_new():
    form = PatientForm()
    if form.validate_on_submit():
        conn = get_db()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """INSERT INTO patients (first_name, last_name, date_of_birth, notes, created_by)
                       VALUES (%s, %s, %s, %s, %s)""",
                    (form.first_name.data, form.last_name.data, form.date_of_birth.data,
                     form.notes.data, session["user_id"]),
                )
            conn.commit()
        finally:
            conn.close()
        logger.info("patient_created by=%s", session.get("full_name"))
        return redirect(url_for("patients_list"))
    return render_template("patient_form.html", form=form)


@app.route("/patients/<int:patient_id>/delete", methods=["POST"])
@login_required
@role_required("medecin")  # la secrétaire ne peut pas supprimer un dossier patient
def patients_delete(patient_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM patients WHERE id = %s", (patient_id,))
        conn.commit()
    finally:
        conn.close()
    logger.info("patient_deleted id=%s by=%s", patient_id, session.get("full_name"))
    return redirect(url_for("patients_list"))


# --- Demandes de rendez-vous déposées par les patients sur le site public ---

@app.route("/rendez-vous")
@login_required
def appointments_list():
    statut = request.args.get("statut", "demande")
    if statut not in ("demande", "confirme", "refuse"):
        abort(400)
    conn = get_db()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
            cur.execute(
                """SELECT a.id, a.reference, a.last_name, a.first_name, a.phone, a.email,
                          a.requested_date, a.slot, a.comment, a.status, a.created_at,
                          s.full_name AS handled_by_name, a.handled_at
                   FROM appointments a
                   LEFT JOIN staff s ON s.id = a.handled_by
                   WHERE a.status = %s
                   ORDER BY a.requested_date, a.created_at""",
                (statut,),
            )
            demandes = cur.fetchall()
    finally:
        conn.close()
    return render_template("appointments.html", demandes=demandes, statut=statut)


@app.route("/rendez-vous/<int:appointment_id>/<decision>", methods=["POST"])
@login_required
def appointments_handle(appointment_id, decision):
    if decision not in ("confirme", "refuse"):
        abort(400)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """UPDATE appointments
                   SET status = %s, handled_by = %s, handled_at = now()
                   WHERE id = %s AND status = 'demande'""",
                (decision, session["user_id"], appointment_id),
            )
        conn.commit()
    finally:
        conn.close()
    logger.info("appointment_handled id=%s decision=%s by=%s",
                appointment_id, decision, session.get("full_name"))
    return redirect(url_for("appointments_list"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
