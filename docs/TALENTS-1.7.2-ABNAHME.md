# FC Teugn Talents 1.7.2 · Mitfahrten und mobile Ansichten

Stand: 8. September 2026. Zielversion: **1.7.2+187**.

## Umsetzung

- Direkte verbindliche Sitzplatzbuchung für das eigene Elternkonto und verknüpfte Kinder, gemeinsam in einem Vorgang. Berechtigte Trainer können Kinder ihrer Terminmannschaften zuordnen.
- Ein Platz je Person; serverseitige Transaktion mit Sperre des Termins schützt auch die letzte freie Sitzposition gegen gleichzeitige Buchungen. Wiederholungen buchen nicht doppelt und erhalten die Familiengruppe.
- Offener Bedarf wird automatisch einem ausreichend großen Angebot zugeordnet. Gemeinsam ausgewählte Personen bleiben in einem Auto. Nicht zuordenbarer Bedarf bleibt offen und rot sichtbar, auch wenn mehrere kleine Autos insgesamt genügend Plätze hätten.
- Stornierung durch Mitfahrer gibt Plätze frei; andere Wartende rücken nach. Rückzug einer Fahrt stellt den Bedarf wieder her. Eine vom Fahrer abgelehnte Fahrt wird bei automatischer Zuordnung übersprungen.
- Bestehende offene Kinderbedarfe für zukünftige freigegebene Termine werden beim Datenbank-Update passenden freien Angeboten zugeordnet. Alte explizite Anfragen bleiben bedienbar; ältere APKs können Erwachseneneinträge weiter lesen.
- Trainer- und Familien-Dashboard sowie die Spieltagsübersicht zeigen freie Plätze, ungedeckten Bedarf und direkte Aktionen. Geöffnete Mitfahransichten aktualisieren sich spätestens alle 30 Sekunden und nach eigenen Änderungen sofort.
- Kompakte Fahrtenkarten mit aufklappbaren Kontaktangaben und Hinweisen. Kurze Buchungsdialoge passen sich ihrer Inhaltslänge an.
- Gemeinsame mobile Seitentitel, Theme-Abstände, Formulare und Dialograhmen wurden verdichtet. Systemschriftvergrößerung bleibt aktiv; Scrollflächen und Bedienaktionen bleiben erreichbar. Der bereits kompakte Autopilot bleibt erhalten.
- Telefonnummern nur für gebuchte Beteiligte beziehungsweise berechtigte Verwaltung; private Bedarfshinweise werden anderen Familien nicht angezeigt. Fremde Mannschaften, fremde Kinder und interne Termine sind gegen unberechtigte Buchung geschützt.
- In-App-Hilfe und Versionshinweise beschreiben die direkte Buchung.

## Interne Prüfung

- Flutter-Formatierung: 291 Dateien geprüft.
- Flutter Analyze: keine Befunde.
- Vollständige Flutter-Suite: **631 Tests bestanden**, einschließlich neun neuer Carpool-Tests, 320/390 Pixel, Hell/Dunkel und 200 % Systemschrift.
- Backend: **272 Tests plus drei vorgeschaltete Tests bestanden**.
- PGlite/PostgreSQL-Integration: alle neun Gruppen bestanden, einschließlich sämtlicher Migrationen mit bestehenden Daten, Erwachsenen-/Kinderbuchungen, automatischer Platzvergabe, Zugriffsrechten und Stornierungen.
- Gerenderte mobile Vorschauen mit synthetischen Daten werden unter `artifacts/release-1.7.2-build-187/` aufbewahrt.
- Zusätzliche parallele HTTP-Buchungen gegen echtes PostgreSQL sind Bestandteil der CI-Abnahme. CI, Release-Builds und öffentliche Auslieferung werden nach Abschluss unten nachgetragen.

Die gemeinsame mobile Basis und die betroffenen Abläufe sind geprüft. Daraus folgt keine Behauptung, jede mögliche Kombination aller App-Fenster auf jedem physischen Telefon visuell abgenommen zu haben.

## Umfang

Android bleibt beim signierten Vereinsdownload mit MagentaCloud-Updates. iPhone bleibt bei der installierbaren Web-App; native Apple-Veröffentlichung ist optional. Keine Mannschaftskasse, keine Google-Play-Veröffentlichung. Interne Tests laufen weiter; Vereinspilot und zusätzliche Abnahmen mit privaten Telefonen werden nicht vorausgesetzt.
