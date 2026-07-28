# Android-Release

Die Android-App verwendet die produktive Kennung `de.fcteugn.jugend` und den
Anzeigenamen `FC Teugn Jugend`. Unterstützt werden Geräte ab Android 6
(`minSdk 23`). Das Release-Manifest enthält die für die HTTPS-API notwendige
Internetberechtigung.

Release-Builds verwenden ohne weitere Konfiguration die produktive API unter
`https://fc-teugn-backend.vercel.app`. Für die lokale Entwicklung am
Android-Emulator kann das Ziel explizit überschrieben werden:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000
```

## Upload-Schlüssel lokal einrichten

Der private Schlüssel und seine Passwörter dürfen niemals in Git eingecheckt
werden. Lege die Keystore-Datei beispielsweise unter
`fc_teugn_app/android/app/upload-keystore.jks` und daneben
`fc_teugn_app/android/key.properties` mit folgendem Inhalt an:

```properties
storePassword=<sicheres-store-passwort>
keyPassword=<sicheres-key-passwort>
keyAlias=upload
storeFile=upload-keystore.jks
```

Danach entsteht das signierte Play-Store-Bundle mit:

```bash
cd fc_teugn_app
FC_TEUGN_REQUIRE_RELEASE_SIGNING=true flutter build appbundle --release
```

`key.properties`, `*.jks` und `*.keystore` sind zentral von Git ausgeschlossen.
Der Upload-Schlüssel muss zusätzlich in einem geschützten Passwortmanager und
an einem zweiten sicheren Ort gesichert werden. Ein verlorener Schlüssel kann
ohne aktivierte Play-App-Signierung die Veröffentlichung von Updates
verhindern.

## Automatischer Nachweis

Die Pull-Request-Pipeline erzeugt ausschließlich für den kurzlebigen
CI-Runner einen temporären Schlüssel und baut damit ein signiertes
Release-App-Bundle. So werden Android-Manifest, Plugins, Gradle-Konfiguration,
Ressourcen und Release-Kompilierung bei jeder Änderung geprüft, ohne einen
produktiven Schlüssel in GitHub Actions offenzulegen.

Vor der ersten Play-Store-Veröffentlichung wird ein dauerhafter
Upload-Schlüssel erzeugt. Dessen Base64-Inhalt, Alias und Passwörter werden als
geschützte GitHub-Environment-Secrets hinterlegt, falls später ein
automatisierter Store-Upload eingerichtet wird.
