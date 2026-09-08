#!/bin/sh
set -eu
config="${FIREBASE_IOS_CONFIG_PATH:-$PROJECT_DIR/Runner/GoogleService-Info.plist}"
target="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/GoogleService-Info.plist"
if [ -f "$config" ]; then
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$config")
  if [ "$bundle_id" != "$PRODUCT_BUNDLE_IDENTIFIER" ]; then
    echo 'error: Firebase iOS configuration belongs to a different bundle identifier.' >&2
    exit 1
  fi
  mkdir -p "$(dirname "$target")"
  cp "$config" "$target"
elif [ "$PLATFORM_NAME" = 'iphoneos' ] && [ "$CONFIGURATION" != 'Debug' ]; then
  echo 'error: Native iPhone release requires the real GoogleService-Info.plist (FIREBASE_IOS_CONFIG_PATH).' >&2
  exit 1
else
  # Do not accidentally reuse configuration from a previous local build.
  if [ -f "$target" ]; then rm "$target"; fi
  echo 'warning: iOS simulator/debug build without Firebase configuration; native push is unavailable.' >&2
fi
