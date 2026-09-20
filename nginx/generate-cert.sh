#!/bin/bash
# Génère un certificat auto-signé pour le lab (à remplacer par un vrai certificat,
# ou une PKI interne, si ce projet devait un jour tourner en dehors du lab).
set -euo pipefail
cd "$(dirname "$0")/certs"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout server.key -out server.crt \
  -subj "/C=FR/ST=Hauts-de-France/L=Arras/O=Cabinet Medical Lab/CN=cabinet-medical.local"

echo "Certificat généré : nginx/certs/server.crt / server.key"
