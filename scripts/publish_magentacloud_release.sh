#!/usr/bin/env bash
set -euo pipefail

apk_path="${1:?Pfad zur signierten APK fehlt}"
: "${MAGENTACLOUD_WEBDAV_USERNAME:?GitHub-Secret MAGENTACLOUD_WEBDAV_USERNAME fehlt}"
: "${MAGENTACLOUD_WEBDAV_PASSWORD:?GitHub-Secret MAGENTACLOUD_WEBDAV_PASSWORD fehlt}"

if [[ ! -f "$apk_path" ]]; then
  echo "Signierte APK nicht gefunden: $apk_path" >&2
  exit 1
fi

app_version="$(awk '/^version:/ { print $2 }' pubspec.yaml)"
version_name="${app_version%%+*}"
version_code="${app_version##*+}"
versioned_name="FC-Teugn-Talents-v${version_name}-build-${version_code}.apk"
latest_name="FC-Teugn-Talents-latest.apk"
manifest_path="$(dirname "$apk_path")/latest.json"
apk_sha256="$(sha256sum "$apk_path" | awk '{ print $1 }')"
apk_size="$(stat -c '%s' "$apk_path")"
published_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
release_key="${version_name}+${version_code}"
release_notes_file="${FC_TEUGN_RELEASE_NOTES_FILE:-release_notes.json}"

# Die Hinweise werden in der App angezeigt. Jede Version muss deshalb einen
# eigenen, bewusst formulierten deutschen Eintrag besitzen. Es gibt absichtlich
# keinen Pauschaltext und keinen Rückfall auf einen technischen Git-Betreff.
if [[ ! -f "$release_notes_file" ]]; then
  echo "Release-Hinweise fehlen: $release_notes_file" >&2
  exit 1
fi

if ! release_notes="$(
  jq -ce --arg releaseKey "$release_key" '
    .[$releaseKey]
    | if type != "array" then
        error("Für " + $releaseKey + " fehlt eine Liste mit Release-Hinweisen.")
      else . end
    | map(
        if type != "string" then
          error("Release-Hinweise müssen Texte sein.")
        else gsub("^\\s+|\\s+$"; "") end
      )
    | if length == 0 or any(. == "") then
        error("Release-Hinweise dürfen nicht leer sein.")
      else . end
  ' "$release_notes_file"
)"; then
  echo "Keine gültigen Release-Hinweise für $release_key gefunden." >&2
  exit 1
fi
public_base="https://magentacloud.de/public.php/dav/files/xkgHEESdKbQ6XMP"
webdav_base="https://magentacloud.de/remote.php/webdav/FC-Teugn/App-Updates"

jq -n \
  --arg versionName "$version_name" \
  --argjson versionCode "$version_code" \
  --arg apkUrl "$public_base/$latest_name" \
  --arg sha256 "$apk_sha256" \
  --argjson fileSize "$apk_size" \
  --arg publishedAt "$published_at" \
  --argjson releaseNotes "$release_notes" \
  '{
    schemaVersion: 1,
    versionName: $versionName,
    versionCode: $versionCode,
    apkUrl: $apkUrl,
    sha256: $sha256,
    fileSize: $fileSize,
    publishedAt: $publishedAt,
    mandatory: false,
    releaseNotes: $releaseNotes
  }' > "$manifest_path"

upload() {
  local source="$1"
  local destination="$2"
  curl \
    --fail \
    --show-error \
    --silent \
    --retry 4 \
    --retry-all-errors \
    --connect-timeout 15 \
    --max-time 900 \
    --user "$MAGENTACLOUD_WEBDAV_USERNAME:$MAGENTACLOUD_WEBDAV_PASSWORD" \
    --upload-file "$source" \
    "$webdav_base/$destination"
}

# Das Manifest wird absichtlich zuletzt veröffentlicht. Dadurch erkennt die
# App eine neue Version erst, nachdem beide APK-Dateien vollständig vorliegen.
upload "$apk_path" "Archiv/$versioned_name"
upload "$apk_path" "$latest_name"
upload "$manifest_path" "latest.json"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "FC_TEUGN_UPDATE_MANIFEST=$manifest_path" >> "$GITHUB_ENV"
fi

echo "MagentaCLOUD-Release $version_name ($version_code) veröffentlicht."
