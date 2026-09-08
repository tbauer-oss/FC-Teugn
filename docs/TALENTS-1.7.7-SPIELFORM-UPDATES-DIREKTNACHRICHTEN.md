# FC Teugn Talents 1.7.7 · Build 193

## Änderungen

- Trainer können im Direktkontakt einzelne Nachrichten oder die gesamte Unterhaltung nach Bestätigung für alle Beteiligten löschen. Der Server prüft Rolle, eigene Empfängerkopie und Mannschaftszugriff. Nachrichtenkopien, Versanddatensätze und private Anhänge werden entfernt. Bei einem Speicherfehler wird kein vollständiger Erfolg gemeldet; Metadaten bleiben für den erneuten Löschversuch erhalten.
- Senden legt sämtliche Empfängerkopien in derselben Transaktion an. Eine Sperre je Unterhaltung ordnet gleichzeitiges Senden und Löschen. Sichtbare Direktkontakte aktualisieren sich alle 30 Sekunden; im Hintergrund pausiert diese Abfrage. Bereits zugestellte Gerätebenachrichtigungen und extern gespeicherte Dateien können nicht zurückgerufen werden. Historische Datenbanksicherungen unterliegen weiterhin der bestehenden Aufbewahrungsfrist.
- Beim Anlegen und Bearbeiten von Spielen und Freundschaftsspielen wird die Spielform pro Spiel gespeichert. Die Auswahl berücksichtigt die Jugend. Bestehende Spiele ohne eigenes Format verwenden weiterhin das Mannschaftsformat. Aufstellung und Autopilot verwenden das wirksame Spielformat; 2 gegen 2, 3 gegen 3 und Fußball 4 auf Minitore planen ohne Torwart.
- Ein Formatwechsel vor Spielbeginn entfernt die bisherige Aufstellung einschließlich geplanter Wechsel. Der Kader bleibt erhalten. Die neue Aufstellung lässt sich passend zum neuen Format planen. Nach Spielbeginn ist ein Formatwechsel gesperrt.
- „Nach Updates suchen“ ist im App-Infofenster und unter „Installation & Updates“ erreichbar. Die manuelle Suche zeigt auch „aktuell“ bzw. Verbindungsfehler an. Beim Aktualisieren der Übersicht läuft die Prüfung unabhängig vom Laden der Mannschaftsdaten. Gleichzeitige Prüfungen werden zusammengefasst, passive Prüfungen höchstens einmal pro Minute ausgeführt.
- Android verwendet den vorhandenen MagentaCLOUD-Download mit Hashprüfung und Android-Installationsbestätigung. Die Web-App vergleicht ihre eingebettete Buildnummer mit der veröffentlichten Version und bietet ein bewusstes Neuladen an.

## Bedienung

- Direktkontakt öffnen: Der Papierkorb an einer Nachricht löscht diese für alle Beteiligten. Der Papierkorb im Kopf der Unterhaltung löscht die gesamte Unterhaltung. Erst „Für alle löschen“ im Bestätigungsdialog führt die Aktion aus. Während des Löschens ist Senden gesperrt; bei einem Fehler bleibt ein vorhandener Entwurf erhalten.
- Spiel oder Freundschaftsspiel anlegen bzw. bearbeiten: Im Feld „Spielform“ das gewünschte Format wählen. Die Mannschaftsvorgabe bleibt unverändert; die Auswahl gilt für dieses Spiel.
- App-Info oder „Installation & Updates“ öffnen und „Nach Updates suchen“ antippen. Zusätzlich wird beim Aktualisieren der Übersicht im Hintergrund nach einer neuen Version gesucht.

## BFV-Grundlage

Stand der Prüfung: 8. September 2026. Die App bildet Spielformen ab; die Durchführung richtet sich zusätzlich nach Jahrgang, Wettbewerb und Kreisfreigabe. Für D-Junioren entspricht 7 gegen 7 dem Zwillingsspielformat je Feld; dessen vollständige Turnierwertung wird durch die Spielformauswahl nicht eingeführt.

- [Minifußball-Richtlinie, 17.04.2026](https://www.bfv.de/binaries/content/assets/inhalt/der-bfv/satzung-richtlinien-amtliches/richtlinien/richtlinie-fur-den-minifussball.pdf): G 2/3, F 3/4/5, E 4/5/7; Fußball 4 mit bzw. ohne Torwart; Jahrgangszuordnung und Spielzeiten.
- [Jugendordnung, 16.07.2026](https://www.bfv.de/binaries/content/assets/inhalt/der-bfv/satzung-richtlinien-amtliches/ordnungen/jugendordnung-ab-16.07.2026.pdf): § 47 kleinere Mannschaften auf Kreisebene bzw. genehmigte Spielformen, § 51 D-Junioren 9 gegen 9 und 7 gegen 7 im Zwillingsspiel.
- [Kleinfeldrichtlinie A–D, 16.07.2026](https://www.bfv.de/binaries/content/assets/inhalt/der-bfv/satzung-richtlinien-amtliches/richtlinien/richtlinien-fur-den-kleinfeldfussball-a--bis-d-junioren.pdf): A–C sieben Spieler, D sechs Spieler einschließlich Torwart unter den dort genannten Voraussetzungen.

## Interne Prüfung

733 Flutter-Tests sowie 304 Backend-Tests und drei vorgeschaltete Prüfungen erfolgreich. Flutter-Analyse ohne Befund. Auch die nativen Android-Pushprüfungen und die vollständige HTTP-Ende-zu-Ende-Abnahme sind bestanden. PostgreSQL-Integration prüft Anlage, sämtliche Spiel-Editoren, Formatvalidierung, Aufstellungsreset, Bestandsschutz laufender Spiele, echtes Senden und vollständiges Löschen samt Anhängen und Versanddaten. Mobile Löschdialoge werden auch bei 320 Pixel Breite geprüft; zusätzliche Tests sichern Entwürfe bei Sende- und Löschfehlern. Die Migration wurde auf einer befüllten Testdatenbank ausgeführt.

Produktive Spiele und Nachrichten wurden nicht als Testdaten verändert. Keine Veröffentlichung bei Google Play.

## Veröffentlichung geprüft

Am 8. September 2026 um 21:45 Uhr MESZ veröffentlicht und öffentlich geprüft. Quellstand: `e7a55ea351b949d2367cc2443bce5e83458813b1`.

- [Backend-Veröffentlichung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34269504147): erfolgreich.
- [Web-Veröffentlichung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34269504113): erfolgreich. Beide Webadressen liefern `1.7.7`, Build `193`; `version.json` wird mit `no-store, max-age=0` ausgeliefert.
- [Vollständige Prüfung und APK-Veröffentlichung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34269504144): erfolgreich, einschließlich Upload zu MagentaCLOUD. Das öffentlich geladene Update-Manifest stimmt mit dem CI-Artefakt überein.
- [Öffentlicher APK-Download](https://magentacloud.de/public.php/dav/files/xkgHEESdKbQ6XMP/FC-Teugn-Talents-latest.apk): heruntergeladen und geprüft; Paket `de.fcteugn.jugend`, Version `1.7.7`, Build `193`, Größe 92.564.866 Byte.
- APK-SHA-256: `b65649228fdc67a7afbbc75f712081c35b90c4c008f269f8450338eafe8994c5`.
- Signatur gültig; unverändertes Android-Update-Zertifikat (SHA-256): `14e38172691d04bcf26210c217c8210301ecd35b3aaa3a18bba2b555f30847bd`.

Lokale Nachweise: `artifacts/release-1.7.7-build-193/public-release-verification.json`, `ci-workflow.json`, `backend-workflow.json`, `web-workflow.json` und `apk-signature.log`.
