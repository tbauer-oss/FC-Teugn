# Nacharbeit und Abnahme 1.7.1+186

Stand: 8. September 2026. Implementiert; abschließende Release-Prüfung und
Veröffentlichung laufen noch. Dieser Bericht erweitert den Stand von 1.7.0+185.

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

## Bisherige Nachweise

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

## Weiterhin externe Abnahme

Keine echten Telefone waren über ADB verbunden. Reale Android-/iPhone-Prüfungen
für Push, Netzunterbrechung, Installation und Startzeiten stehen aus. Der Pilot
mit zwei Trainern und fünf Eltern ist vorbereitet, aber nicht durchgeführt.
Eine gemessene Überlegenheit gegenüber der BFV-Team-App wird nicht behauptet.

Für TestFlight/App Store fehlen die zugeordneten Apple-Signierungsdaten und
die reale Firebase-Apple-/APNs-Konfiguration. Für die Store-Veröffentlichungen
sind die zugehörigen Entwicklerkonten erforderlich. Einrichtung und Grenzen:
[iOS-Auslieferung](ios-release.md). Die Mannschaftskasse bleibt ausgeschlossen.
