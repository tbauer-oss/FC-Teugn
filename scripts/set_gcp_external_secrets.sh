#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-fc-teugn}"

gcloud projects describe "$PROJECT_ID" >/dev/null
gcloud config set project "$PROJECT_ID" --quiet

ensure_secret() {
  local name="$1"
  if ! gcloud secrets describe "$name" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud secrets create "$name" --project "$PROJECT_ID" --replication-policy automatic >/dev/null
  fi
}

store_secret() {
  local name="$1"
  local value="$2"
  ensure_secret "$name"
  printf '%s' "$value" | gcloud secrets versions add "$name" \
    --project "$PROJECT_ID" --data-file=- >/dev/null
}

printf '\nFC Teugn Talents – externe Produktions-Secrets\n'
printf 'Die Eingaben werden nicht angezeigt und nicht in Dateien gespeichert.\n\n'

read -r -s -p 'Produktive Neon DATABASE_URL einfügen: ' DATABASE_URL
echo
if [[ "$DATABASE_URL" != postgres://* && "$DATABASE_URL" != postgresql://* ]]; then
  echo 'DATABASE_URL sieht nicht wie eine PostgreSQL-Verbindungszeichenfolge aus.' >&2
  unset DATABASE_URL
  exit 1
fi

read -r -s -p 'Neuen Resend API Key einfügen: ' RESEND_API_KEY
echo
if [[ "$RESEND_API_KEY" != re_* ]]; then
  echo 'Der Resend API Key hat nicht das erwartete re_ Präfix.' >&2
  unset DATABASE_URL RESEND_API_KEY
  exit 1
fi

store_secret DATABASE_URL "$DATABASE_URL"
store_secret RESEND_API_KEY "$RESEND_API_KEY"

unset DATABASE_URL RESEND_API_KEY

echo 'DATABASE_URL und RESEND_API_KEY wurden sicher in Google Secret Manager gespeichert.'
echo 'Die eingegebenen Werte wurden nicht ausgegeben oder lokal gespeichert.'
