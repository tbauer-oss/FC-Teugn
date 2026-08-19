#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export PATH="$SCRIPT_DIR/flutter/bin:$PATH"
flutter build web --release --tree-shake-icons

# These assets are native-only. Flutter records every pubspec asset in the web
# build even when the web launch path can never request it. Removing the intro
# video and native splash variants saves roughly 9 MB per web deployment while
# the dedicated web splash remains available.
rm -f \
  build/web/assets/assets/video/fc_teugn_talents_intro.mp4 \
  build/web/assets/assets/branding/fc_teugn_talents_mobile_startscreen.png \
  build/web/assets/assets/branding/fc_teugn_talents_splash.png
