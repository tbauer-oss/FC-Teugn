#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/fc_teugn_app"

if [ ! -d "$APP_DIR" ]; then
  echo "fc_teugn_app directory not found at $APP_DIR" >&2
  exit 1
fi

cd "$APP_DIR"
bash ./vercel_install.sh
