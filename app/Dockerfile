FROM python:3.12-slim

WORKDIR /app

# libpq-dev/gcc : nécessaires pour compiler psycopg2 à l'installation
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# L'appli ne tourne jamais en root dans le conteneur
RUN useradd --create-home appuser
USER appuser

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
