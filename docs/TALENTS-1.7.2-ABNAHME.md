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
- Parallele HTTP-Buchungen gegen echtes PostgreSQL in CI: bestanden. Bei zwei Anfragen für den letzten Sitzplatz wird genau eine Buchung mit 201 bestätigt; die zweite erhält 409. Die gemeinsame Eltern-/Kinderzuordnung belegt anschließend genau zwei von fünf Plätzen.

Die gemeinsame mobile Basis und die betroffenen Abläufe sind geprüft. Daraus folgt keine Behauptung, jede mögliche Kombination aller App-Fenster auf jedem physischen Telefon visuell abgenommen zu haben.

## Umfang

Android bleibt beim signierten Vereinsdownload mit MagentaCloud-Updates. iPhone bleibt bei der installierbaren Web-App; native Apple-Veröffentlichung ist optional. Keine Mannschaftskasse, keine Google-Play-Veröffentlichung. Interne Tests laufen weiter; Vereinspilot und zusätzliche Abnahmen mit privaten Telefonen werden nicht vorausgesetzt.

## Veröffentlichung und öffentliche Abnahme

Ausgelieferter Quellstand: `024d49fd5778294653ab0c6e8bc847d509653a28`.

- [Release-Prüfung und Android-Veröffentlichung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34207384799): erfolgreich; Backend, Migrationen, HTTP-E2E, Flutter Analyze/Tests, Web-Build und signierte APK.
- [Backend-Auslieferung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34207384792): erfolgreich einschließlich der Mitfahrtenmigration.
- [Web-Auslieferung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34207384946): erfolgreich.
- [Vorbereitende Build-Prüfung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34206711028): erfolgreich auf `52fea8c`, einschließlich signierter APK und AAB als Build-Artefakt. Die abschließenden mobilen Details sind in der obigen Release-Prüfung enthalten. Keine Google-Play-Einreichung.

Öffentlich geprüft am 8. September 2026:

- [Web-App](https://fcteugnapp.vercel.app): Version **1.7.2, Build 187**.
- Backend: Health `ok`, geschützter Endpunkt `401`, ungültige Einladung mit Datenbankzugriff `410`. Keine Produktions-Testdatensätze angelegt.
- [MagentaCloud-Download](https://magentacloud.de/s/xkgHEESdKbQ6XMP): öffentliche APK vollständig heruntergeladen; Version, Dateigröße und SHA-256 stimmen mit `latest.json` überein.
- APK: 92,401,006 Bytes; veröffentlicht `2026-09-08T09:07:54Z`. SHA-256: `d857e06221c2861566cb2a62f0f050df12fcfdfca33e79b2ee806ae97e427436`.
- APK-Signatur geprüft und identisch mit dem bisherigen Vereinszertifikat: `14e38172691d04bcf26210c217c8210301ecd35b3aaa3a18bba2b555f30847bd`.
- Öffentlich heruntergeladene APK als direktes Update **1.7.1+186 → 1.7.2+187** im isolierten Android-Emulator installiert. Ursprünglicher Installationszeitpunkt bleibt erhalten; App startet, Prozess läuft weiter und der Crash-Puffer bleibt leer.
- Kein Test auf einem privaten Telefon und keine neue Push-Zustellprüfung behauptet.

Nachweise unter `artifacts/release-1.7.2-build-187/`: `live-verification.json`, `android-update-verification.json`, Signatur-/Paketdaten, CI-/Testprotokolle, gerenderte mobile Mitfahransichten und Screenshot des APK-Starts.
