# Elternstart A und Familie B

Umsetzung des bestätigten Entwurfs: weiße, reduzierte Elternstartseite mit Kinderfiltern, offenen Rückmeldungen, nächstem Training **und** nächstem Spiel; getrennte Familienübersicht je Kind. Die Navigation heißt Start, Termine, Spiele, Postfach, Familie. Traineroberflächen bleiben unverändert.

## Bedienung und bestehende Funktionen

- Jede Rückmeldung gehört zu **Termin + Kind**. Auch Geschwister im selben Training haben separate Aktionen. Zusagen/Absagen aktualisieren beide Übersichten nach bestätigtem Speichern.
- Spielkarten zeigen Gegner, Beginn und Treffpunkt. Auswärtsrouten nutzen die vorhandene Adressauflösung und echte Routenschätzungen ab Teugn. Keine feste Beispielentfernung im Produktcode.
- Kader & Spielinfo öffnet den Spieltag; Turniere öffnen die Turnierplanung. Trainingslinks berücksichtigen den Zielmonat, noch nicht im Kalender materialisierte Regeltrainings öffnen die persönliche Rückmeldung.
- Abwesenheiten und Trainerkontakt stehen direkt unter den Kindern. Weitere Familienfunktionen erhalten Regeltrainings-Zusagen, Profile/Dokumente, Aufgaben/Dienste, Ausrüstung, Umfragen, Lernziele, Statistiken, Ergebnisse, Datenschutz, Hilfe und Support.
- Konto, Mannschaftswechsel, Darstellung, Aktualisierung, Installation und Abmelden sind im Profilmenü weiterhin erreichbar.
- Rückmeldefristen gelten unverändert. Nach Ablauf führt die Oberfläche zum Trainerkontakt. Admin-Lesevorschauen können keine Rückmeldungen ändern.
- Alte Pushlinks `/parent/family?eventId=...&playerId=...` bleiben gültig. Neue Antwortübersichten nutzen `/parent/responses` mit optionalem Kinder-/Offenfilter.

## Veröffentlichungshinweis

**Zuerst Backend, danach App veröffentlichen.** Die neue Postfachvorschau verwendet `GET /communications/family-contact?preview=1`. Dieser Modus verändert weder Lesebestätigungen noch Aufbewahrungsdaten. Ein altes Backend ignoriert den Parameter und könnte Nachrichten als gelesen markieren. Der normale Aufruf beim bewussten Öffnen des Direktkontakts behält sein bisheriges Verhalten. Berechtigungen und Empfängerscope wurden nicht erweitert.

In dieser Umsetzung erfolgte keine Veröffentlichung und kein Test mit produktiven Nachrichten oder Rückmeldungen.

## Prüfung

- Finaler vollständiger Flutter-Testlauf: **825 Tests bestanden**. Statische Analyse der App und der neuen Tests: ohne Befund.
- Neue Widget-/Interaktionstests prüfen zwei Kinder, gemeinsame Trainings, direkte Zusage, Absagegrund, Speicherfehler, Fristablauf, Lesevorschau, Navigation, Schriftvergrößerung sowie schmale, breite und querformatige Displays.
- Screenshot-Aufnahmen aus den echten Flutter-Widgets mit ausdrücklich fiktiven Testdaten: `artifacts/parent-home/start.png`, `familie.png`, `start-dark.png`.
- Backendtest `family-contact-preview.test.js` prüft mehrfaches Polling ohne Schreibzugriff, Empfänger-/Mannschaftsbegrenzung und das unveränderte Lesen beim Öffnen des Postfachs. Er ist in die bestehende Benachrichtigungs-Testsuite eingebunden.
