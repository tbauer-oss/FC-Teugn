#!/usr/bin/env bash
set -euo pipefail

export PATH="$PWD/flutter/bin:$PATH"
flutter build web --release
