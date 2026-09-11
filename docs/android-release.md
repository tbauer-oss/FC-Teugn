# Android-Release

Nutzerentscheidung vom 8. September 2026: Keine Veröffentlichung bei Google
Play. Der verbindliche Auslieferungsweg ist die signierte APK über MagentaCloud
einschließlich des vorhandenen Vereins-Updaters. Eine separate Play-Version
wird nicht umgesetzt. Die unten beschriebene AAB-Erzeugung dokumentiert einen
vorhandenen technischen Buildweg und ist kein noch offener Veröffentlichungsschritt.

Die Android-App verwendet die produktive Kennung `de.fcteugn.jugend` und den
Anzeigenamen `FC Teugn Talents`. Mit Flutter 3.44.8 werden Geräte ab Android 7
(`minSdk 24`) unterstützt. Das Release-Manifest enthält die für die HTTPS-API notwendige
Internetberechtigung.

Release-Builds verwenden ohne weitere Konfiguration die produktive API unter
`https://app.fc-teugn-talents.de/api`. Für die lokale Entwicklung am
Android-Emulator kann das Ziel explizit überschrieben werden:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000
```

## Automatische App-Updates über MagentaCLOUD

Vor jedem Release müssen `fc_teugn_app/pubspec.yaml` (Version und Build),
`fc_teugn_app/lib/core/app_update/app_release.dart` (dieselbe Buildnummer für die
laufende Web-App) und der passende Eintrag in `fc_teugn_app/release_notes.json`
gemeinsam aktualisiert werden. Erst danach die Tests ausführen. Der Test
`update_check_coordinator_test.dart` verhindert unterschiedliche Buildnummern.

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

Ein manueller CI-Lauf veröffentlicht nichts. Für die anschließende Freigabe
wird `release_google.yml` mit der erfolgreichen `validation_run_id` gestartet.
Pushes auf main/master veröffentlichen nach erfolgreicher Validierung automatisch.
Backend, Web und Android-Artefakt müssen aus demselben getesteten Commit stammen.

`update_policy.json` legt die mindestens unterstützte Android-Buildnummer fest.
Build 195 prüft Pflichtupdates vor der Anmeldung und bleibt auch bei abgebrochener
Installation gesperrt. Bei einer nicht erreichbaren ersten Versionsprüfung bietet
er einen erneuten Versuch an. Bereits installierte Builds 193/194 können diese
neue Sperre nicht nachträglich erhalten: ihr alter Dialog bleibt nach dem Start
von Androids Installer umgehbar. Die beibehaltene API-Weiterleitung ermöglicht
ihren Start, und das kompatible Manifest setzt dort `mandatory: true`.
Neuere Clients berücksichtigen zusätzlich `minimumSupportedBuild`, sodass nicht
jede nachfolgende Verbesserung erneut ein Pflichtupdate auslöst.

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

Ein AAB kann nicht direkt auf dem Telefon installiert werden. Für den hier
vorgesehenen Vereinsdownload ausschließlich die signierte APK verwenden.
Das AAB wird nicht bei Google Play eingereicht.
