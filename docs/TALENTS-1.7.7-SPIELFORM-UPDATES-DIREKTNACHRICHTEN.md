# FC Teugn Talents 1.7.7 · Build 193

## Änderungen

- Trainer können im Direktkontakt einzelne Nachrichten oder die gesamte Unterhaltung nach Bestätigung für alle Beteiligten löschen. Der Server prüft Rolle, eigene Empfängerkopie und Mannschaftszugriff. Nachrichtenkopien, Versanddatensätze und private Anhänge werden entfernt. Bei einem Speicherfehler wird kein vollständiger Erfolg gemeldet; Metadaten bleiben für den erneuten Löschversuch erhalten.
- Senden legt sämtliche Empfängerkopien in derselben Transaktion an. Eine Sperre je Unterhaltung ordnet gleichzeitiges Senden und Löschen. Sichtbare Direktkontakte aktualisieren sich alle 30 Sekunden; im Hintergrund pausiert diese Abfrage. Bereits zugestellte Gerätebenachrichtigungen und extern gespeicherte Dateien können nicht zurückgerufen werden. Historische Datenbanksicherungen unterliegen weiterhin der bestehenden Aufbewahrungsfrist.
- Beim Anlegen und Bearbeiten von Spielen und Freundschaftsspielen wird die Spielform pro Spiel gespeichert. Die Auswahl berücksichtigt die Jugend. Bestehende Spiele ohne eigenes Format verwenden weiterhin das Mannschaftsformat. Aufstellung und Autopilot verwenden das wirksame Spielformat; 2 gegen 2, 3 gegen 3 und Fußball 4 auf Minitore planen ohne Torwart.
- Ein Formatwechsel vor Spielbeginn entfernt die bisherige Aufstellung einschließlich geplanter Wechsel. Der Kader bleibt erhalten. Die neue Aufstellung lässt sich passend zum neuen Format planen. Nach Spielbeginn ist ein Formatwechsel gesperrt.
- „Nach Updates suchen“ ist im App-Infofenster und unter „Installation & Updates“ erreichbar. Die manuelle Suche zeigt auch „aktuell“ bzw. Verbindungsfehler an. Beim Aktualisieren der Übersicht läuft die Prüfung unabhängig vom Laden der Mannschaftsdaten. Gleichzeitige Prüfungen werden zusammengefasst, passive Prüfungen höchstens einmal pro Minute ausgeführt.
- Android verwendet den vorhandenen MagentaCLOUD-Download mit Hashprüfung und Android-Installationsbestätigung. Die Web-App vergleicht ihre eingebettete Buildnummer mit der veröffentlichten Version und bietet ein bewusstes Neuladen an.

## BFV-Grundlage

Stand der Prüfung: 8. September 2026. Die App bildet Spielformen ab; die Durchführung richtet sich zusätzlich nach Jahrgang, Wettbewerb und Kreisfreigabe. Für D-Junioren entspricht 7 gegen 7 dem Zwillingsspielformat je Feld; dessen vollständige Turnierwertung wird durch die Spielformauswahl nicht eingeführt.

- [Minifußball-Richtlinie, 17.04.2026](https://www.bfv.de/binaries/content/assets/inhalt/der-bfv/satzung-richtlinien-amtliches/richtlinien/richtlinie-fur-den-minifussball.pdf): G 2/3, F 3/4/5, E 4/5/7; Fußball 4 mit bzw. ohne Torwart; Jahrgangszuordnung und Spielzeiten.
- [Jugendordnung, 16.07.2026](https://www.bfv.de/binaries/content/assets/inhalt/der-bfv/satzung-richtlinien-amtliches/ordnungen/jugendordnung-ab-16.07.2026.pdf): § 47 kleinere Mannschaften auf Kreisebene bzw. genehmigte Spielformen, § 51 D-Junioren 9 gegen 9 und 7 gegen 7 im Zwillingsspiel.
- [Kleinfeldrichtlinie A–D, 16.07.2026](https://www.bfv.de/binaries/content/assets/inhalt/der-bfv/satzung-richtlinien-amtliches/richtlinien/richtlinien-fur-den-kleinfeldfussball-a--bis-d-junioren.pdf): A–C sieben Spieler, D sechs Spieler einschließlich Torwart unter den dort genannten Voraussetzungen.

## Interne Prüfung

730 Flutter-Tests sowie 304 Backend-Tests und drei vorgeschaltete Prüfungen erfolgreich. Flutter-Analyse ohne Befund. PostgreSQL-Integration prüft Anlage, sämtliche Spiel-Editoren, Formatvalidierung, Aufstellungsreset, Bestandsschutz laufender Spiele, echtes Senden und vollständiges Löschen samt Anhängen und Versanddaten. Mobile Löschdialoge werden auch bei 320 Pixel Breite geprüft. Die Migration wurde auf einer befüllten Testdatenbank ausgeführt.

Produktive Spiele und Nachrichten wurden nicht als Testdaten verändert. APK, Web und Backend werden über die vorhandenen Veröffentlichungsabläufe bereitgestellt; keine Veröffentlichung bei Google Play.
