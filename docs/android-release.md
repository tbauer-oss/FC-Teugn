# Android-Release

Die Android-App verwendet die produktive Kennung `de.fcteugn.jugend` und den
Anzeigenamen `FC Teugn Talents`. Mit Flutter 3.44.8 werden Geräte ab Android 7
(`minSdk 24`) unterstützt. Das Release-Manifest enthält die für die HTTPS-API notwendige
Internetberechtigung.

Release-Builds verwenden ohne weitere Konfiguration die produktive API unter
`https://fc-teugn-backend.vercel.app`. Für die lokale Entwicklung am
Android-Emulator kann das Ziel explizit überschrieben werden:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000
```

## Automatische App-Updates über MagentaCLOUD

Android-Releases werden nach erfolgreicher Prüfung zusätzlich in den
öffentlichen MagentaCLOUD-Ordner `FC-Teugn/App-Updates` veröffentlicht. Die
App liest beim Start ausschließlich das maschinenlesbare `latest.json`. Eine
neuere Version wird mit Versionsnummer und Änderungshinweis angeboten. Vor
der Übergabe an den Android-Paketinstaller werden Dateigröße und SHA-256 der
APK geprüft.

Die GitHub-Actions-Secrets
`MAGENTACLOUD_WEBDAV_USERNAME` und
`MAGENTACLOUD_WEBDAV_PASSWORD` enthalten eine getrennte WebDAV-Sitzung und
niemals das normale Telekom-Kontopasswort. Der Workflow lädt zuerst die
versionierte APK ins `Archiv`, ersetzt anschließend
`FC-Teugn-Talents-latest.apk` und veröffentlicht `latest.json` zuletzt.

Android verlangt bei einer direkt verteilten APK einmalig die Freigabe
„Unbekannte Apps installieren“ für FC Teugn Talents und anschließend bei
jeder Version die Bestätigung des System-Installationsdialogs. Eine stille
Installation ohne diese Android-Sicherheitsdialoge ist nicht möglich.

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

## Automatischer Nachweis und Veröffentlichung

Die Pipeline `Validate FC Teugn Talents` prüft zuerst das Backend einschließlich
Migrationen und HTTP-Abnahme gegen PostgreSQL. Danach folgen Flutter-Analyse,
Tests, Web-Build und Android-Kompilierung. Pull Requests bauen eine Debug-APK
ohne Zugriff auf den permanenten Signaturschlüssel.

Pushes auf `main`/`master` und manuelle Läufe bauen eine dauerhaft signierte APK.
Manuelle Läufe erzeugen zusätzlich ein signiertes Android App Bundle (AAB).
Die vorhandenen GitHub-Secrets `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` und `ANDROID_KEY_PASSWORD`
liefern die Signatur. Der Workflow entfernt die temporären Schlüsseldateien
anschließend auch im Fehlerfall.

Ein manueller Lauf veröffentlicht standardmäßig nichts. `publish_android`
aktiviert die Auslieferung ausdrücklich. Vor jedem öffentlichen Android-Upload
müssen Backend und Web für **denselben Commit** erfolgreich ausgerollt sein.
Die Web-Auslieferung wartet ebenfalls auf das Backend. Ein fehlgeschlagener,
noch laufender oder fremder Deploymentlauf gibt das Update nicht frei.

Release-Builds dürfen nach einem Debug-Gerätetest nicht mit `--no-pub` gestartet
werden: Flutter muss die Pluginregistrierung für den Release-Modus neu erzeugen,
damit das ausschließlich für Tests eingebundene `integration_test` entfällt.

## Lokaler signierter Build unter Windows

Mit dem vorhandenen, für das Windows-Benutzerkonto verschlüsselten
Signaturdatensatz kann im Projektverzeichnis gebaut werden:

```powershell
./scripts/build_android_release.ps1 -FlutterSdk 'C:/Pfad/zu/flutter'
```

Das Skript erzeugt APK und AAB, entschlüsselt die benötigten Werte nur für den
Build und entfernt die selbst erzeugte `key.properties` anschließend. Eine
bereits vorhandene Signaturkonfiguration bleibt erhalten. Ausgaben liegen unter
`fc_teugn_app/build/app/outputs/flutter-apk/app-release.apk` und
`fc_teugn_app/build/app/outputs/bundle/release/app-release.aab`.

Ein AAB ist für die Einreichung bei Google Play gedacht; ein Store-Upload ist
ein zusätzlicher Schritt mit einem eingerichteten Play-Entwicklerkonto.
