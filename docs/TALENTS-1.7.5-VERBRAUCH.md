# FC Teugn Talents 1.7.5+190 – Neon-Verbrauch

## Ausgangslage am 8. September 2026

Neon zeigte 44,68 von 100 CU-Stunden seit Monatsbeginn bei nur 0,05 GB Datenbankinhalt. Der produktive Compute war mit mindestens 0,25 CU und fünf Minuten automatischer Ruhefrist konfiguriert. In den Vercel-Protokollen lief `/internal/cron/reminders` nachweislich alle fünf Minuten. Die Abfragen selbst waren kurz; die wiederkehrenden Zugriffe verhinderten längere Ruhephasen. 0,25 CU bei durchgehendem Betrieb ergeben rechnerisch 180 CU-Stunden in 30 Tagen.

## Änderungen

- Der Fünf-Minuten-Takt für fällige Erinnerungen bleibt erhalten. Ein gemeinsamer Vercel Runtime Cache merkt sich ausschließlich den nächsten Arbeitszeitpunkt und eine Änderungsrevision. Liegt keine Arbeit an, beantwortet der Cron den Aufruf ohne Datenbankabfrage.
- Die Planung berücksichtigt Erinnerungen, geplante Mitteilungen, Trikotdienst, Kalenderimporte, Trainingszeiten, offene Zustellungsaufträge, private Löschfristen und den Berliner Tageswechsel. Mindestens stündlich erfolgt ein vollständiger Kontrolllauf.
- Schreibvorgänge verwerfen die Leerlaufentscheidung zu Beginn und nach Abschluss. Die Cache-Zugriffe laufen über `waitUntil`, sodass sie Speichern und Toreingabe nicht aufhalten. Neue Daten während einer laufenden Bestandsaufnahme machen deren Revision ungültig. Eine sechsminütige Schutzfrist übersteigt die in den produktiven Vercel-Protokollen ausgewiesene maximale Funktionslaufzeit von fünf Minuten. Die automatische Express-Laufzeit verwendet diesen Wert trotz der älteren 30-Sekunden-Konfiguration für api/index.ts.
- Fehlende, abgelaufene oder fehlerhafte Cache-Leseergebnisse führen zur normalen Verarbeitung. Ein rein lokaler Cache wird nicht zur Entscheidung über gemeinsame Aufträge verwendet. Das SDK prüft zur Laufzeit die verfügbare gemeinsame Cache-Anbindung.
- Die stündliche Trainingspflege wird im gleichen Lauf erledigt; der zusätzliche, zeitversetzte Cron entfällt. Ein Fehler dieser Pflege blockiert die übrigen fälligen Nachrichten nicht.
- Allgemeine Aufräumarbeiten laufen täglich. Private Familienkontakte behalten ihre eigene fristgerechte Löschung. Abgelaufene Idempotenzantworten werden direkt beim Zugriff verworfen.
- Gleichzeitige Liveticker-Zuschauer teilen innerhalb einer laufenden Backend-Instanz die Prüfung auf Änderungen. Eigene Tore wecken sie sofort; für Änderungen anderer Instanzen bleibt das 450-ms-Intervall bestehen. Jede HTTP-Anfrage prüft weiterhin ihre eigenen Zugriffsrechte und vor Rückgabe erneut die aktuelle Freigabe.
- Automatische App-Abfragen pausieren im Hintergrund. Der Spieltag pausiert zusätzlich hinter anderen Seiten und nimmt die Live-Verbindung unmittelbar bei Rückkehr wieder auf. Erste Ladeanfragen bleiben direkt.

## Interne Nachweise

- Backend-Build und vollständige Backend-Tests bestanden; einschließlich neuer Tests für Leerlauf, Cache-Ausfall, konkurrierende Änderungen, cronbedingte Zeitabweichungen, Sommer-/Winterzeit, Löschfristen, Wartung und HTTP-Autorisierung.
- Vollständiger Flutter-Testlauf mit 721 Tests bestanden. Anschließend zusätzlicher Widget-Test für den tatsächlichen Spieltag: Hintergrundpause, Rückkehr, verdeckende Seite, erneute Live-Verbindung und sauberes Beenden. Alle sechs gezielten Tests bestanden. Flutter-Analyse ohne Befund.
- Isolierte PostgreSQL-Integration mit sämtlichen Migrationen bestanden, einschließlich Gastspielern, beiden Elternzugängen, Liveticker-Zugriff, Buchungen und Entzug von Einladungen. Keine produktiven Testdaten oder Testnachrichten.
- Lokaler Vergleich bei 100 Zuschauern und unverändertem 450-ms-Takt: innerhalb einer ruhigen Sekunde 300 auf 2 Sequenzabfragen; bei einem eigenen Tor 100 auf 1. Die lokale Benachrichtigung erfolgte in beiden Fassungen im selben Messschritt. Eine simulierte Änderung aus einer anderen Instanz wurde nach 399 ms beziehungsweise 414 ms erkannt. Das ist ein Vergleich des Ablaufs mit einem Speicher-Stub, keine Messung realer Neon-Netzwerklatenz und keine CU-Einsparungsprognose.

Nachweise liegen unter `artifacts/release-1.7.5-build-190/`.

## Betrieb und Grenzen

Die effektive CU-Ersparnis hängt davon ab, wie lange die App aktiv genutzt wird, ob fällige Aufträge bestehen und ob weitere Anwendungen dieselbe Datenbank ansprechen. Der Freitarif kann deshalb nicht garantiert werden. Der erste echte Datenbankzugriff nach einer Ruhephase benötigt das normale Neon-Aufwachen; im laufenden Betrieb gibt es keine zusätzliche Wartezeit durch die neue Planung.

Cache-Invalidierung ist ein bestmöglicher Vorgang der Vercel-Infrastruktur. Der stündliche Kontrolllauf begrenzt Auswirkungen externer Datenbankänderungen oder eines Ausfalls während der Invalidierung. Für direkte Änderungen außerhalb dieser API, die neue kurzfristige Aufträge anlegen, muss ebenfalls invalidiert werden. `NEON_IDLE_GUARD_DISABLED=true` mit erneutem Backend-Deployment schaltet die Leerlaufunterdrückung bei Bedarf ab.

Die Veröffentlichung und der Nachweis echter Leerlaufläufe werden nach Abschluss ergänzt.
