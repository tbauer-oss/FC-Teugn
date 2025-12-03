#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_SLUG="${VERCEL_PROJECT_SLUG:-fc-teugn-backend}"

if [[ -z "${VERCEL_TOKEN:-}" ]]; then
  echo "VERCEL_TOKEN is required to link the backend to Vercel. Export it before running this script." >&2
  exit 1
fi

cd "$API_DIR"
vercel link --project "$PROJECT_SLUG" --yes --token "$VERCEL_TOKEN"
