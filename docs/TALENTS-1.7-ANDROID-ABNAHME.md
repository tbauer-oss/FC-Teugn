# Android-Abnahme 1.7.0+185

Durchgeführt am 7. September 2026 auf einem eigens angelegten, isolierten
Android-Emulator (API 37.1, x86_64). Das vorhandene Benutzer-AVD wurde nicht
verändert. Testkonten und Daten stammen ausschließlich aus der lokalen
Integrationsdatenbank.

## Ergebnis

- Signierte APK und AAB erfolgreich erstellt; APK mit `apksigner`, AAB mit
  `jarsigner` verifiziert.
- Signatur identisch mit dem veröffentlichten CI-Artefakt von 1.6.46+184.
  Zertifikat-SHA-256:
  `14e38172691d04bcf26210c217c8210301ecd35b3aaa3a18bba2b555f30847bd`.
- Installation von 1.6.46+184 und direktes Update mit `adb install -r` auf
  1.7.0+185 erfolgreich. Die erste Installationszeit blieb erhalten;
  Versionsname und Buildnummer wechselten wie erwartet.
- Die installierte Release-App startet bis zur korrekt dargestellten Anmeldung.
- Automatisierter Gerätetest: anmelden, Umfrage erstellen, Abwesenheit speichern,
  Umfrage erneut öffnen und gespeicherten Inhalt bestätigen. Ergebnis: bestanden.
- Dabei gefundene Aktualisierungsfehler in Umfragen, Abwesenheiten, Einladungen
  und Lernzielen behoben. Ein zusätzlicher Widgettest prüft das tatsächliche
  Aktualisieren der Umfragenseite nach erfolgreichem Speichern.

## Gemessene Zeiten und ihre Grenzen

| Messung | Ergebnis | Bedeutung |
|---|---:|---|
| Android `am start -W`, neuer Release nach Update | 1.202 ms | Native Activity-Startmessung im Emulator; kein Nachweis vollständig geladener Mannschaftsdaten. |
| Vorhandene Activity aus dem Hintergrund holen | 55 ms Wartezeit | Android brachte den bestehenden Task nach vorne; keine neue Activity gestartet. |
| Flutter-Start bis sichtbare Anmeldung im Integrationstest | 2.050 ms | Debug-Build, einschließlich Erststartlogik mit übersprungenem Intro. |

Diese unterschiedlichen Messungen dürfen nicht zu einer behaupteten
Warmstartzeit auf echten Telefonen zusammengefasst werden. Der vereinbarte
Warmstart-Zielwert sowie Zustellung und Einstieg per Push müssen weiterhin auf
echten Geräten mit angemeldeten Konten geprüft werden.

## Wiederholung

Die isolierte API wird aus dem Projektverzeichnis gestartet:

```sh
npm ci --prefix api/test-support
node api/tests/talents-integration.cjs --serve
```

Danach im App-Verzeichnis mit laufendem Testemulator:

```sh
flutter test integration_test/talents_device_test.dart -d <Emulator-ID> --dart-define=API_BASE_URL=http://10.0.2.2:4000
```

Der Test verweigert öffentliche API-Adressen. Er erzeugt ausschließlich Daten
in der isolierten Testdatenbank. Bei Windows-Java-Socketproblemen den in der
[Android-Release-Anleitung](android-release.md) beschriebenen lokalen Buildweg
verwenden. Nach Gerätetests Release-Builds ohne `--no-pub` ausführen.

Lokale Dateien und Prüfprotokolle liegen unter
`artifacts/release-1.7.0-build-185/`. Sie werden nicht in das öffentliche
Quelltext-Repository aufgenommen. Die CI veröffentlicht separat ihre
geprüften Artefakte und bei Freigabe das Android-Update.
