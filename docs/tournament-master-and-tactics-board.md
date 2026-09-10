# Turnier-Master und trainerinternes Taktikboard

## Turnierplanung

- Kader und Rückmeldungen werden am Turnier verwaltet. Einzelpartien bieten einen direkten Einstieg zum Turnierkader, keine zweite Nominierung.
- Beim Öffnen einer Partie werden auch alte, abweichende Einzelspiel-Kader und Rückmeldungen mit dem Master abgeglichen. Eltern- und Trainer-Antworten werden einschließlich Zeitpunkt und Herkunft übernommen.
- Die Turnieraufstellung ist die Ausgangsaufstellung der Partien. Eine bewusst angepasste Einzelspiel-Aufstellung bleibt erhalten. Bei bereits gestarteten Spielen bleibt der historische Kader bestehen; die Rückmeldung kommt weiterhin vom Turnier.
- Turnierpartien sind keine konkurrierenden Tages-Einladungen und werden bei einer Turnier-Zusage nicht automatisch abgesagt.
- Im Turnierplan können einzelne oder alle Partien entfernt werden. Erst „Speichern“ und die ausdrückliche Löschbestätigung löschen diese einschließlich Aufstellungen, Ergebnissen und Ereignissen. Der Turnierkader bleibt erhalten. Dafür ist `MATCH_DELETE` nötig.
- Die API verlangt die exakte Liste `removedFixtureIds`. Zwischenzeitlich hinzugefügte/entfernte Partien führen zu einem Konflikt statt einer unbeabsichtigten Löschung. Löschungen erhalten Audit-Einträge.

## Taktikboard

Einstieg: **Spiel → Aufstellung → Taktikboard**, auch aus der vergrößerten Aufstellung. Für Trainer mit `MANAGE_LINEUPS` und Zugriff auf die Mannschaft.

- Übernimmt die aktuell angezeigte Aufstellung als Ausgangspunkt, verändert aber nie den tatsächlichen Kader, die Aufstellung oder den Liveticker.
- Eigene Spieler und Gegner verschieben/beschriften, Ball und Text hinzufügen, freihändig zeichnen, Passpfeile, Laufwege und Räume markieren.
- Bis zu acht benannte Spielzüge; duplizieren, umbenennen, löschen, rückgängig/wiederholen. Präsentationsmodus blendet Werkzeuge aus. Das Werkzeug „Zoom“ vergrößert das Feld; „Zentrieren“ setzt die Ansicht zurück.
- Explizites Speichern pro Spiel, separat in `MatchTacticsBoard`. Keine Veröffentlichung an Familien und keine Push-Nachrichten. Die API prüft Trainerberechtigung und Mannschaft auch unabhängig vom Button.
- Gleichzeitiges Speichern ist revisionsgesichert. Bei Konflikten oder Verbindungsfehlern bleibt der offene Entwurf erhalten; kein stilles Überschreiben und kein späteres Einreihen eines veralteten Speicherstands in die Offline-Warteschlange.
- Ungespeicherte Änderungen werden beim Verlassen bestätigt. Entwürfe sind bis zum Speichern nur im offenen Board vorhanden, nicht nach einem App-Abbruch garantiert wiederherstellbar.
- Smartphone: horizontal scrollbare Werkzeuge. Breitere Fenster: seitliche Werkzeugleiste. Größen-/Orientierungswechsel erhalten die Zeichnung; Safe Areas und physisch trennende Scharniere werden berücksichtigt. Spielerbeschriftungen sind diagrammtypisch kompakt, vollständige Namen über Tooltip/Semantik und Zoom verfügbar.

## Veröffentlichung und Prüfung

Release-Ziel: **1.8.5+199**. Vor Nutzung ist die Migration `20260910170000_match_tactics_board` nötig. Der bestehende Google-Release-Workflow führt die Migration vor dem Backend-Deployment aus und veröffentlicht anschließend Web-App und signiertes Android-Update. Ein lokaler Testlauf verändert keine Produktionsdaten.

## Moderne Aufstellung

- Eine gemeinsame Oberfläche für Spieltag und Vollbild; flaches smaragdgrünes Spielfeld, Trikots mit Nummern, Torwart in Gelb und Kapitänskennzeichnung.
- Kurznamen auf dem Feld, vollständige Namen beim Antippen/Bearbeiten und auf der Ersatzbank. Feldpositionen bleiben normalisierte taktische Koordinaten; Größenwechsel verändern keine gespeicherte Aufstellung.
- Breitere Fenster nutzen Feld und Bedienleiste nebeneinander, Smartphones eine vertikal scrollbare Oberfläche. Bei dichten Formationen und großer Schrift ist das Feld gezielt seitlich verschiebbar, ohne Seiten-Overflow. Physische Scharniere werden ausgespart.
- Formation, automatische Aufstellung, Verschieben, Spieler-/Positionswechsel, Torwart/Kapitän, Bank, Speichern, internes Teilen und Familienfreigabe bleiben erhalten. Taktikboard und echte Aufstellung speichern unabhängig voneinander.
- `modern_lineup_view_test.dart`: wechselnde Breiten 320–900 px, Querformat, Schrift bis 200 %, elf Spieler, Scharnier, Familienansicht und erreichbare Aktionen. Visuelle Prüfbilder optional über `CAPTURE_UI`.

Prüfungen:

- `npm test`: Backend-Regressionssuite einschließlich Dokumentvalidierung.
- `npm run test:talents:integration`: isolierte PostgreSQL-kompatible Testdatenbank mit allen Migrationen; echte Controller-/Datenbankabläufe, Trainerantworten, Altbestandsreparatur, Familienberechtigungen, Einzel-/Sammellöschung, Speicherrevisionen und Taktik-Cascade.
- Flutter: `tactics_board_test.dart`, `tournament_matchday_planning_test.dart`, `match_squad_responsive_test.dart`; Gesten, Speicher-/Schließkonflikte, Trainer-Einstieg und Master-Anzeige.
- Dynamische Board-Breiten 320/360/375/390/412/430/650/850 px, Querformat, vergrößerte Schrift und simuliertes Scharnier; optionale lokale Bildausgabe über `CAPTURE_UI` und `UI_FONT_PATH`.

Widget- und Datenbanktests ersetzen keinen abschließenden Gerätetest der veröffentlichten Android-/iOS-App.
