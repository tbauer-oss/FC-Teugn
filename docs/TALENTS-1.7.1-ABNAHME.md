# Nacharbeit und Abnahme 1.7.1+186

Stand: 8. September 2026. **1.7.1+186 ist veröffentlicht.** Web-App, Backend und
Android-Vereinsdownload wurden erfolgreich ausgeliefert; der öffentliche
Download wurde um 09:13 Uhr MESZ geprüft. Dieser Bericht erweitert 1.7.0+185.

## Änderungen

- Autopilot: „Organisation“ ist standardmäßig eingeklappt und zeigt nur den
  Status. Offene Punkte stehen beim Öffnen zuerst. Einsatzzeiten besitzen eine
  eigene Aufklappfunktion. Checklisten, Unterlagen, Dienste und Verbandslinks
  bleiben erreichbar. Im Widgettest mit 390 Pixel Breite und 150 Prozent
  Schriftgröße bleibt die geschlossene Karte unter 110 logischen Pixeln Höhe.
- Lernziele: „Verlauf & Statistik“ führt Zielbeobachtungen mit bestehenden
  Entwicklungsnotizen, abgeschlossenen Spielen und tatsächlich erfasster
  Trainingsanwesenheit im Zielzeitraum zusammen. Grenzen folgen den Berliner
  Kalendertagen einschließlich des letzten Zieltags. Geplante, abgesagte oder
  für Familien unveröffentlichte Spiele werden nicht als erfasste Familienleistung
  ausgegeben. Ein gemeinsamer Rückblick lässt sich kopieren und als PDF speichern.
- Rechte: Nur das zuständige Trainerteam oder die zugeordnete Familie darf ein
  freigegebenes Ziel lesen. Private Entwicklungsnotizen bleiben im Trainerteam;
  der alte Mannschaftszugang eröffnet nach Saisonwechsel keinen Zugriff auf
  private Notizen der neuen Mannschaft.
- Native iOS-Push-Mitteilungen: Implementierung in App und Backend, eigene
  Plattformkennung `IOS`, Tokenwechsel, Warten auf APNs, sichtbare Meldungen im
  Vordergrund und Navigation aus Push-Mitteilungen. Androids besondere
  Live-Spielanzeige wird auf iOS als reguläre Push-Mitteilung ausgeliefert.
  Geräteverwaltung und Versanddiagnose unterscheiden iOS, Android und Web.
- Migration `20260908110000_native_ios_push` ergänzt ausschließlich einen Wert
  im vorhandenen Push-Plattformtyp; vorhandene Daten bleiben erhalten.

## Nachweise

- Backend: 272 Tests und 3 Vorabtests erfolgreich.
- Flutter: vollständige Suite mit 622 erfolgreichen Tests; Analyse ohne Befunde.
- Isolierte Datenbank: 8 Integrationsgruppen erfolgreich, einschließlich
  Migration mit bestehenden Daten, Sichtbarkeitsrechten, Datumsgrenzen,
  tatsächlichen statt geplanten Anwesenheiten und iOS-Gerätetyp.
- Gezielte Flutter-Prüfungen: kompakte Autopilot-Darstellung und Bedienung,
  Entwicklungsansicht bei 200 Prozent Schrift auf 320 Pixel Breite,
  Exportinhalte, APNs-Warteverhalten und iOS-Registrierungsdaten.
- Lokaler Screenshot mit echten Schriftdateien aus dem Widgettest:
  `artifacts/release-1.7.1-build-186/autopilot-mobile.png`.
- Browserprüfung mit isolierter API und synthetischen Trainer-/Familienkonten:
  Anmeldung, archiviertes Ziel, gemeinsamer Verlauf, Exportvorschau und Rückweg
  erfolgreich. Private Trainernotiz und unveröffentlichtes Spiel erscheinen beim
  Trainer; beide fehlen in der Familienansicht. Die freigegebene Notiz und
  Zielbeobachtung bleiben dort sichtbar.
- Android: Direktes Update von 1.7.0+185 auf 1.7.1+186 im isolierten Emulator
  erfolgreich, ursprünglicher Installationszeitpunkt erhalten. App-Prozess
  nach dem Start aktiv. Gemessener kalter Activity-Start: 2293 ms; das ist kein
  Nachweis der vollständig geladenen Oberfläche oder des Warmstartziels auf
  einem echten Telefon. Die anschließend aus MagentaCloud heruntergeladene
  Produktions-APK ließ sich ebenfalls über die bestehende Installation installieren.
- Native iOS-App: erfolgreicher Simulator-Build auf macOS; geprüftes Bundle
  `de.fcteugn.jugend`, Version 1.7.1, Build 186. Hintergrundmodi und deaktivierte
  automatische Firebase-Tokeninitialisierung sind im Bundle enthalten.
  Das bestätigt die Kompilierbarkeit, keine Push-Zustellung auf einem iPhone.
- Signierte APK und AAB erfolgreich erstellt und Signaturen geprüft.

## Veröffentlichung

Ausgelieferter Quellstand: `b0ca73843a3aa7cf000b3c08197a37a290a2a486`.
Die native iOS-Kompilierung erfolgte auf `3b88e99`; die anschließende Änderung
betraf ausschließlich deutsche Singular-/Pluraltexte und diesen Bericht.

- [Vollständige Prüfung einschließlich iOS](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34195548335): erfolgreich.
- [Prüfung des abschließenden Quellstands](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34196103333): erfolgreich.
- [Backend-Veröffentlichung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34197308460): erfolgreich, einschließlich der iOS-Plattformmigration.
- [Web-Veröffentlichung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34197308449): erfolgreich.
- [Produktionsprüfung und Android-Veröffentlichung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34197308471): erfolgreich, einschließlich APK und Aktualisierungsmanifest in MagentaCloud.

Öffentlich geprüft:

- [Web-App](https://fcteugnapp.vercel.app): Version 1.7.1, Build 186;
  Anmeldung und Installationsseite im Browser erreichbar.
- [Backend](https://fc-teugn-backend.vercel.app): Health `ok`, geschützter
  Endpunkt ohne Anmeldung `401`; datenbankgestützte Prüfung einer ungültigen
  Einladung liefert `410`. Keine Produktionsdatensätze wurden dafür angelegt.
- [APK in MagentaCloud](https://magentacloud.de/s/xkgHEESdKbQ6XMP):
  öffentlich heruntergeladen, 92.319.162 Bytes, Version 1.7.1, Build 186;
  Dateigröße und SHA-256 stimmen mit `latest.json` überein.
  Veröffentlichungszeit im Manifest: `2026-09-08T07:12:25Z`.
- SHA-256 der öffentlichen APK:
  `a1777d054fb1d81ecc54b1fbf15f1e45b7a5d0712049efd2f16415a2413d2d0b`.
- `apksigner verify` bestätigt die gültige APK-Signatur mit dem bisherigen
  Vereinszertifikat; Zertifikat-SHA-256:
  `14e38172691d04bcf26210c217c8210301ecd35b3aaa3a18bba2b555f30847bd`.

Lokale Nachweise liegen unter `artifacts/release-1.7.1-build-186/`, darunter
`live-verification.json`, `android-update-verification.json` und
`ios-bundle-verification.json`.

## Weiterhin externe Abnahme

Keine echten Telefone waren über ADB verbunden. Reale Prüfungen der Android-APK
und iPhone-Web-App für Push, Netzunterbrechung, Installation und Startzeiten stehen aus. Der Pilot
mit zwei Trainern und fünf Eltern ist vorbereitet, aber nicht durchgeführt.
Eine gemessene Überlegenheit gegenüber der BFV-Team-App wird nicht behauptet.

Umfang nach anschließender Nutzerentscheidung vom 8. September 2026:

- Google Play entfällt vollständig. Android bleibt bei APK und MagentaCloud-Updates.
- Native Apple-Veröffentlichung ist vorerst optional. Die dafür erforderliche
  Apple-Signierung, native Firebase-/APNs-Konfiguration und native Geräteabnahme
  sind spätere Ausbauschritte, keine offenen Pflichtpunkte.
- Installation und Web-Push der iPhone-Web-App bleiben Teil der praktischen
  Abnahme. Dafür ist kein kostenpflichtiges Apple-Entwicklerkonto erforderlich.
- Verbindlich offen bleiben Startzeitmessungen auf echten Geräten, die genannten
  Geräteprüfungen und der Vereinspilot. Diese Punkte werden erst nach realer
  Durchführung mit Ergebnissen abgeschlossen.

Einrichtung des optionalen nativen Ausbaus: [iOS-Auslieferung](ios-release.md).
Die Mannschaftskasse bleibt ausgeschlossen.
