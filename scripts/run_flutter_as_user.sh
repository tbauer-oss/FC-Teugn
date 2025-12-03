#!/usr/bin/env bash
set -euo pipefail

# Helper to run Flutter commands as an unprivileged user to avoid root warnings.
TARGET_USER=${FLUTTER_USER:-flutterdev}
FLUTTER_BIN=${FLUTTER_BIN:-flutter}

if [ "$(id -u)" -ne 0 ]; then
  exec "$FLUTTER_BIN" "$@"
fi

# Ensure the target user exists with a home directory for Flutter caches.
if ! id "$TARGET_USER" >/dev/null 2>&1; then
  echo "Creating user '$TARGET_USER' for Flutter tool cache..."
  useradd --create-home --shell /bin/bash "$TARGET_USER"
fi

USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [ -z "$USER_HOME" ]; then
  echo "Could not determine home directory for $TARGET_USER" >&2
  exit 1
fi

# Run the Flutter command as the unprivileged user, preserving PATH and HOME.
if command -v sudo >/dev/null 2>&1; then
  exec sudo -E -u "$TARGET_USER" HOME="$USER_HOME" PATH="$PATH" bash -c "cd \"$PWD\" && exec \"$FLUTTER_BIN\" \"$@\"" -- "$@"
fi

exec su - "$TARGET_USER" -c "cd \"$PWD\" && HOME=\"$USER_HOME\" PATH=\"$PATH\" exec \"$FLUTTER_BIN\" \"$@\""
