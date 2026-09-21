#!/bin/bash
# Certificat auto-signé pour le lab, à remplacer par un certificat reconnu
# si ce service devait être réellement exposé à des patients.
set -euo pipefail
cd "$(dirname "$0")/certs"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout server.key -out server.crt \
  -subj "/C=FR/ST=Hauts-de-France/L=Arras/O=Cabinet Medical Lab/CN=rdv.cabinet-medical.local"

echo "Certificat généré : nginx/certs/server.crt / server.key"
