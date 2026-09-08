# FC Teugn Talents – Umsetzung und Abnahme

Stand: 7. September 2026. App-Version: **1.7.0+185 ist veröffentlicht**. Web-App, Backend und Android-Vereinsdownload wurden nach vollständiger CI-Abnahme ausgeliefert und öffentlich geprüft. Details: [Veröffentlichungsnachweis](TALENTS-1.7-VEROEFFENTLICHUNG.md).

Historische Statuskorrektur vor 1.7.1, vom 8. September 2026: Der gesamte Umsetzungsplan war noch nicht abgeschlossen. Zusätzlich zur praktischen Abnahme fehlten die vollständige Verbindung der Lernziele mit bestehenden Entwicklungsdaten und die native iOS-Push-Implementierung. Beide Softwareteile wurden mit 1.7.1 ergänzt. Der Vereinspilot wurde vorbereitet, aber noch nicht durchgeführt. Erfolgreiche automatisierte Prüfungen ersetzen die praktische Abnahme nicht.

Die Mannschaftskasse ist auf ausdrücklichen Wunsch vollständig ausgeschlossen. Es gibt dafür weder neue Seiten noch API-Endpunkte oder Datenbanktabellen. Ohne BFV-API bleiben offizielle Spielberichte, Spielberechtigungen und Festivalmeldungen im BFV-/SpielPLUS-System.

Aktualisierung für 1.7.1+186: Die beiden fehlenden Softwareteile und die kompakte Autopilot-Übersicht sind veröffentlicht. Aktueller Prüf- und Veröffentlichungsstand: [Abnahme 1.7.1](TALENTS-1.7.1-ABNAHME.md). Die folgenden Tabellen und Nachweise dokumentieren weiterhin die vorherige Version 1.7.0+185.

## Umgesetzte Bereiche

| Paket | Ergebnis im Projekt |
|---|---|
| 1. Kalenderabgleich | BFV-iCal und manuelle Importe verwenden denselben Änderungsdienst. Der Vergleich zwischen letztem Import, lokalem Stand und neuer Quelle erhält unabhängige lokale Änderungen. Konfliktfelder sind einzeln auswählbar. Verlegungen erhalten eine Änderungshistorie, planen Erinnerungen neu und fordern gegebenenfalls eine erneute Antwort an. Alte Antworten bleiben nachvollziehbar. Fehlende Kalendereinträge werden nicht als Absage interpretiert. |
| 2. Nachrichten | Dauerhaft gespeicherte Versandaufträge für Terminänderungen, Umfragen und Einladungsprüfung; bestehende Push-Kategorien, Versandwiederholung und Duplikatschutz werden verwendet. Vor Umfrageerinnerungen werden offene Stimmen, Frist und aktuelle Berechtigungen erneut geprüft. Das Öffnen führt in den passenden Rollenbereich. |
| 3. Start | Intro beim ersten Start, zunächst stumm und überspringbar; freiwillige Wiederholung unter „Über die App“. Direkte Einstiege und Push-Nachrichten umgehen das Intro. Die vorhandene Router- und Hintergrundaktualisierung bleibt bestehen. |
| 4. Navigation | Neuer Bereich „Familie & Team“ für Trainer und Familien. Registrierung heißt „App-Zugang“. Die Zahl offener Familienaufgaben stammt aus derselben Aufgabenliste wie das Ziel. Direkte Wege, Bereichsmarkierung und Hilfe sind verbunden. |
| 5. Abwesenheiten | Zeitraum, Wiederholungswochentage, Mannschaften und Terminarten pro Kind; automatische Berücksichtigung bestehender und später angelegter Termine. Spätere Einzelantworten sind Ausnahmen. Bearbeiten und vorzeitiges Beenden stellen frühere Antworten für künftige Termine wieder her. Der optionale Grund bleibt im berechtigten Bereich. |
| 6. Familien-Assistent | Rückmeldungen, Einwilligungen, offene Umfragestimmen, eigene Teamaufgaben, Trikotdienst und Mitfahrvorgänge mit Kind, Frist und Handlungslink. Erledigte Aufgaben verschwinden nach bestätigtem Speichern. Änderungen erscheinen mit alten und neuen Angaben. Überschneidungen werden für bekannte Anfangs- und Endzeiten erkannt. |
| 7. Spieltags-Assistent | Bereitschaft für Antworten, Fahrgemeinschaften, Trikotdienst und Checklisten im Autopiloten. Wiederverwendbare Vorlagen für Heimspiel, Auswärtsspiel und Turnier. Geplante und dokumentierte Einsatzminuten werden gegenübergestellt und erklärt; Trainerentscheidungen und Veröffentlichungsregeln bleiben erhalten. |
| 8. Umfragen | Einfach- und Mehrfachauswahl, eine Stimme je Person/Familie/Kind, Frist, änderbare Antworten, Teilnahmezahl und Ergebnissichtbarkeit. Verknüpfte Eltern teilen Familienstimmen. Gezieltes Erinnern, Abschließen und Archivieren; Einstieg auch aus Nachrichten. |
| 9. Einladungen | Befristeter, widerrufbarer Link mit QR-Code, Mannschaft und vorgesehener Rolle. Vorhandene Konten können eine weitere Mannschaft beantragen. App-Zugang, Mannschaftsfreigabe und Kinderprüfung bleiben getrennte nachvollziehbare Schritte. Eine Familienrolle wird nicht stillschweigend zur Trainerrolle. |
| 10. Lernziele – teilweise umgesetzt | Höchstens drei aktive Ziele pro Kind, verantwortlicher Trainer, Zeitraum, Übungen und Trainingspläne. Eigene Zielbeobachtungen, Fortschritt, Abschluss/Archiv und Sichtbarkeit für die Familie. Der Rückblick enthält Ziele und deren eigene Beobachtungen als kopierbare Übersicht beziehungsweise PDF. Der Statistikzugang ist bisher ein allgemeiner Navigationslink; die gemeinsame Darstellung mit bestehenden Entwicklungsnotizen und Statistikdaten des Kindes fehlt. |
| 11. Mannschaftskasse | Entfällt vollständig. |
| 12. Spieltagsunterlagen | Kopierbare und druckbare PDF-Übersichten mit Termin, Treffpunkt, Ausrüstung, Kader, Einsatzzeiten und organisatorischem Stand. Kontextzugang zu BFV/SpielPLUS; Kalenderquelle und vereinsintern gepflegte Angaben sind gekennzeichnet. |
| 13. Saisonwechsel | Übernahmeentscheidungen für aktive Ziele und Abwesenheiten, konkrete Anzahl in der Vorschau und Hinweise auf zu prüfende Verantwortliche/Zeiträume. Originalziele bleiben archiviert, übernommene Ziele erhalten eine neue Saisonzuordnung. Familienverknüpfungen bleiben bestehen; wiederholte Ausführung dupliziert keine Ziele. |
| 14. Installation | Gemeinsame Seite für Android und iPhone, mit Plattformwahl, Vereinsdownload, PWA-Schritten, Updatehinweisen und Rückweg zur Einladung. Verknüpft aus Anmeldung und „Über die App“. Bestehende signierte APK-/AAB-Pipeline bleibt die Auslieferungsgrundlage. Integrierte Hilfe erweitert; zusätzliche Schulungs- und Pilotanleitung siehe unten. |
| 15. Qualität | Neue Aktionen benötigen bewusst eine Online-Verbindung. Formulare behalten Eingaben bei Fehlern. Eine beim Benutzer gespeicherte Vorgangskennung schützt Wiederholungen auch nach Neustart; private Formulare werden dafür nicht lokal gespeichert. Schreibvorgang und Ergebnis werden serverseitig atomar gespeichert. Migration, Rollen, Fremdzugriff, Familienabstimmungen, Kalenderänderungen und Saisonhistorie werden geprüft. Datenschutzexport und Kontolöschung berücksichtigen die neuen Daten. |

## Nachweise

- Backend: vollständige Suite mit **271 erfolgreichen Tests**, dazu **3 erfolgreiche Vorabtests** für biometrische Anmeldung.
- Flutter: vollständige Suite mit **617 erfolgreichen Tests**, einschließlich der Regressionstests für direkte Einstiege nach Browser-Neuladen und das Aktualisieren nach gespeicherten Umfragen. Zusätzliche Prüfungen umfassen Importdialog, Navigation, Hilfe, Releasehinweise und Talents-Formulare.
- Flutter-Analyse: **keine Befunde**.
- Migration und Fachabläufe: **7 erfolgreiche Integrationsgruppen**, einschließlich aller vorhandenen Migrationen, Upgrade mit vorher angelegten Datensätzen, fehlender Kassentabellen, tatsächlicher Datenbanktransaktionen, Rollenprüfung und Idempotenz.
- Web: Release-Build erfolgreich. Im lokalen Browser wurden Anmeldung, Navigation, Formulare, das Speichern einer Umfrage mit anschließendem Wiederaufruf sowie Einladungslink und QR-Code geprüft. Ausschließlich synthetische Konten und Daten; keine Nachrichten an reale Vereinsmitglieder.
- Android: Debug-APK erfolgreich kompiliert. Der anfängliche Java-Socketfehler ließ sich durch ein projektnahes Socket-Verzeichnis beheben.
- Android-Release: APK und AAB wurden mit dem vorhandenen Vereinsschlüssel erfolgreich gebaut. Die APK-Signatur wurde mit `apksigner verify` geprüft. Der lokal verschlüsselte Signaturdatensatz wird über `scripts/build_android_release.ps1` verwendet; die dafür kurzzeitig angelegte `key.properties` wird anschließend entfernt.
- Release-Reihenfolge: Vier automatisierte Tests prüfen die Freigabe anhand des exakten Commits. Web wartet auf das Backend; die öffentliche Android-Auslieferung wartet auf Backend und Web. Manuelle Validierung erzeugt standardmäßig nur Artefakte.
- iOS: Eigenständige Bundle-ID, iOS-15-Deploymentziel und Swift-Package-Manager-Integration durch Flutter ergänzt. Nativer Simulator-Build auf macOS erfolgreich; ZIP-Artefakt gesichert. Der native Push-Dienst unterstützt im Code bisher nur Android. Für native iOS-Push-Mitteilungen fehlen sowohl die Implementierung als auch die Konfiguration und Geräteabnahme; zusätzlich sind Apple-Signierung und reale Entwicklerzugänge für die Store-Auslieferung erforderlich.
- Android-Gerätetest auf isoliertem Emulator: Anmeldung, Umfrage und Abwesenheit speichern, Daten erneut öffnen; bestanden. Direktes Update der signierten Version 1.6.46+184 auf 1.7.0+185 ebenfalls bestanden. Messwerte und Grenzen: [Android-Abnahme](TALENTS-1.7-ANDROID-ABNAHME.md).

Die isolierte Integrationsdatenbank verwendet PGlite mit PostgreSQL-Abfragen und einem Prisma-Pool von einer Verbindung. Ein zusätzlicher echter PostgreSQL-Lauf ist in der CI erfolgreich abgeschlossen: Registrierung, Freigabe, Elternzuordnung, Training, Teilnahme, Spiel, Kader, Aufstellung, Ticker mit zwei Clients, Korrektur, Statistik und Administratorlöschung. Diese Abnahme ist kein Lasttest mit produktiven Vereinsdaten.

## Noch ausstehende Umsetzung und Abnahme

Die ersten beiden Punkte enthalten noch Softwarearbeit. Weitere Schritte benötigen passende Geräte, Vereinsmitglieder beziehungsweise Veröffentlichungszugänge. Die Checkliste wurde entsprechend korrigiert:

1. Lernziele mit den bestehenden Entwicklungsnotizen und Statistikdaten des jeweiligen Kindes zusammenführen. Eigene Zielbeobachtungen und ein allgemeiner Link zur Statistik erfüllen diesen Listenpunkt noch nicht vollständig.
2. Native iOS-Push-Mitteilungen implementieren, mit Firebase/APNs konfigurieren und auf einem iPhone prüfen. Ein erfolgreicher Simulator-Build ist hierfür kein Funktionsnachweis.
3. Android und iPhone auf echten Geräten: Installation, Update, Push-Einstieg, Netzunterbrechung, Erststart und Warmstart messen. Die angestrebten etwa zwei Sekunden Warmstart sind noch kein gemessener Wert auf echten Telefonen.
4. Store-Freigaben mit Entwicklerkonten und Apple-Signierung. Die native iOS-Kompilierung ist nachgewiesen; die iPhone-PWA ist der verfügbare Installationsweg.
5. Alltagspilot mit zwei Trainern und fünf Eltern durchführen und auswerten. Bisher existieren Anleitung und Erfassungsbogen, aber keine Messwerte. Erst ein durchgeführter Vergleich kann belegen, ob die App für FC Teugn schneller und verständlicher ist als die BFV-Team-App.

## Lokale Prüfungen wiederholen

Aus dem Projektverzeichnis:

```powershell
npm.cmd ci --prefix api/test-support --cache tmp/npm-cache
npm.cmd test --prefix api
npm.cmd run test:talents:integration --prefix api
```

Im Verzeichnis `fc_teugn_app` mit eingerichteter Flutter-Umgebung:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web --release --no-pub
flutter build apk --debug
```

Falls die Windows-JVM im Codex-Prozess `Unable to establish loopback connection` meldet, kann für diesen Build ein vorhandenes beschreibbares Projektverzeichnis als `jdk.net.unixdomain.tmpdir` gesetzt werden. Die hier erfolgreiche Einstellung erfolgte nur für den gestarteten Prozess, ohne globale Java-Konfiguration zu ändern. Hintergrund: [OpenJDK-Hinweis zum Socket-Verzeichnis unter Windows](https://mail.openjdk.org/pipermail/nio-dev/2023-March/013297.html).

## Ablauf künftiger Veröffentlichungen

1. Datenbanksicherung und Staging prüfen; Migration `20260907120000_talents_family_development` mittels des vorhandenen Prisma-Deploymentablaufs anwenden. Migration vor dem neuen Backend bereitstellen.
2. Backend bereitstellen und Erreichbarkeit prüfen. `PUBLIC_APP_URL` muss auf den vorgesehenen Frontendhost zeigen; Standard ist `https://fcteugnapp.vercel.app`.
3. Vorhandenen geschützten Cronlauf weiter betreiben: Er wendet Abwesenheiten an und verarbeitet Terminänderungen, neue Versandaufträge und Erinnerungen.
4. Web und signierte Android-Version über die vorhandenen Workflows bereitstellen. Der Vereinsdownload bietet seit dieser Abnahme 1.7.0+185 an; die öffentlich geladene Datei stimmt mit Dateigröße und SHA-256 des Manifests überein und ist mit dem Vereinsschlüssel signiert.
5. Smoke-Test als Trainer und Familie, dann Pilot durchführen. Bei Rücknahme des Codes die neuen Tabellen und historischen Antworten erhalten; keine destruktive Rückmigration auf einer befüllten Datenbank improvisieren.

Schulungs- und Pilotaufgaben: [TALENTS-1.7-SCHULUNG-UND-PILOT.md](TALENTS-1.7-SCHULUNG-UND-PILOT.md).
