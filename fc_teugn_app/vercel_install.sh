#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION=3.22.2
FLUTTER_TAR="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_TAR}"

curl -L "$FLUTTER_URL" | tar -xJ
export PATH="$PWD/flutter/bin:$PATH"
git config --global --add safe.directory "$PWD/flutter"
flutter config --no-analytics
flutter --version
flutter pub get
