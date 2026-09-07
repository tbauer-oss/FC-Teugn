# Veröffentlichung von FC Teugn Talents 1.7.0+185

Abgeschlossen und öffentlich geprüft am **7. September 2026, 21:37 Uhr MESZ**.
Die Mannschaftskasse ist vollständig ausgeschlossen.

## Verfügbare Version

- [Web-App](https://fcteugnapp.vercel.app): `version.json` meldet 1.7.0, Build 185.
- Browser-Abnahme: Anmeldung, Installationsseite, Wechsel zwischen Android und
  iPhone-Anleitung sowie Rückkehr zur Anmeldung erfolgreich geprüft.
- [Android-Vereinsdownload](https://magentacloud.de/s/xkgHEESdKbQ6XMP): signierte
  Version 1.7.0, Build 185, einschließlich der neuen Releasehinweise.
- Backend produktiv erreichbar. Neue geschützte Route liefert ohne Anmeldung
  HTTP 401; eine synthetische ungültige Einladung liefert nach tatsächlicher
  Datenbankabfrage HTTP 410. Keine Testkonten oder Testeinträge in der Produktion
  angelegt.

Geprüfter und ausgerollter Quelltext-Commit:
`85999b182ef0c57f35b6b74d0b0af0b994fcfa53`.

## Automatische Nachweise

| Prüfung / Auslieferung | Ergebnis |
|---|---|
| [Release-Abnahme mit iOS, Android und PostgreSQL](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34154583262) | Erfolgreich |
| [Produktive Backend-Auslieferung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34155605441) | Erfolgreich |
| [Produktive Web-Auslieferung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34155605453) | Erfolgreich |
| [Produktive Android-Auslieferung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34155605427) | Erfolgreich |

271 Backend-Tests und drei Vorabtests, 617 Flutter-Tests, sieben zusätzliche
Migrations-/Integrationsgruppen und die HTTP-Abnahme gegen PostgreSQL bestanden.
Flutter-Analyse ohne Befunde. APK, AAB und iOS-Simulator-App erfolgreich gebaut.
Android-Update und tatsächliche Formularabläufe im Emulator bestanden:
[Android-Abnahme](TALENTS-1.7-ANDROID-ABNAHME.md).

## Öffentlicher Android-Download

Die APK wurde nach Veröffentlichung erneut vom öffentlichen Vereinsdownload
geladen. Dateigröße **92.220.814 Bytes** und SHA-256 stimmen exakt mit dem
Update-Manifest überein:

```text
e83a9b7102989e9ba89a160f0905480787b91fd21d606dc3c75c14e7a4abb032
```

`apksigner verify` bestätigt die Signatur. Zertifikat-SHA-256:

```text
14e38172691d04bcf26210c217c8210301ecd35b3aaa3a18bba2b555f30847bd
```

Dies entspricht dem Vereinsschlüssel der bisher veröffentlichten 1.6.46+184.
Öffentlicher Download, CI-Artefakte, iOS-ZIP und lokale Prüfergebnisse liegen
unter `artifacts/release-1.7.0-build-185/`; private Signaturdateien wurden nicht
in Git aufgenommen.

## Weitere Veröffentlichungen

Backend und Web werden über GitHub Actions bereitgestellt. Web wartet auf das
Backend für denselben Commit, Android auf Backend und Web. Die zusätzlich
vorgefundene Vercel-Git-Automatik ist in der Projektkonfiguration deaktiviert,
damit parallele Deployments diese Reihenfolge künftig nicht umgehen.
Konfigurationskorrektur: `08d0bcd` (keine Änderung am App-Quelltext).

Noch extern erforderlich sind Store-Konten und Freigaben, Apple-Signierung und
native iOS-Push-Einrichtung sowie Tests auf echten Telefonen und der Pilot mit
zwei Trainern und fünf Eltern. Simulator- und Build-Ergebnisse ersetzen diese
Abnahmen nicht. Die iPhone-PWA kann bereits installiert werden.
