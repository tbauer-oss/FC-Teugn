# FC Teugn Talents im Vergleich zur BFV-Team-App

Stand: 7. September 2026. Geprüfter Projektstand: Version 1.6.46+184, Commit `aae7793` vom 3. September 2026.

> Historischer Vergleich vor der Umsetzung. Die Mannschaftskasse wurde anschließend auf Nutzerwunsch vollständig ausgeschlossen. Den aktuellen Stand beschreibt [Umsetzung und Abnahme](UMSETZUNGSSTAND-TALENTS-2026-09-07.md).

## Urteil und Prüfgrenzen

FC Teugn Talents hat bereits einen breiten Funktionsumfang für Jugendmannschaften und Familien. Ein Ausbau zu einer im Vereinsalltag besseren App ist plausibel. Eine insgesamt überlegene Bedienbarkeit oder Zuverlässigkeit ist damit noch nicht nachgewiesen: Dafür braucht es vergleichbare Alltagstests auf echten Geräten.

Diese Einschätzung beruht auf dem aktuellen Flutter-Code, Backend, Datenmodell und ausgewählten vorhandenen Tests sowie den öffentlichen BFV-Produktinformationen. Anmeldung und Registrierung von FC Teugn Talents wurden zusätzlich im Browser angesehen. Es stand dort keine angemeldete Sitzung zur Verfügung. Geschützte Abläufe, produktive Push-Zustellung und Android-/iPhone-Bedienung wurden in dieser Prüfung nicht praktisch getestet. Die BFV-App wurde anhand offizieller Beschreibungen und Versionshinweise verglichen, nicht mit einem angemeldeten Mannschaftskonto.

„Vorhanden“ bedeutet hier im Code nachvollziehbar umgesetzt. „Nicht gefunden“ ist eine Aussage über diesen Projektstand. Eine Funktion, die der BFV in den geprüften Quellen nicht beschreibt, wird nicht als fehlend gewertet. Ältere Abschlussberichte und Release Notes wurden nicht ungeprüft als aktueller Stand übernommen.

## Funktionsvergleich

| Bereich | BFV-Team-App | FC Teugn Talents | Bewertung |
|---|---|---|---|
| Termine und Rückmeldungen | Training, Serien, Fristen, Zu-/Absagen [1] | Kalender, Serien, Familienrückmeldungen, Erinnerungen, ICS-Abonnement | Kernumfang vorhanden; Alltagstempo prüfen. |
| Eltern und mehrere Kinder | Verknüpfung auch über Teams und Vereine hinweg [1] | Eltern-Kind-Beziehungen, mehrere Mannschaften, Familien-Assistent | Gute Basis für FC-Teugn-Familien; vereinsübergreifende Nutzung nicht praktisch belegt. |
| Offizielle Spieltermine | Direkte SpielPLUS-Synchronisierung [1, 2] | Automatischer BFV-iCal-Abgleich, CSV-/ICS-Import, Konfliktschutz | Bereits deutlich mehr als manueller Import; keine gleichwertige vollständige SpielPLUS-Synchronisierung. |
| Spieler und offizieller Spielbericht | Spielberechtigungsliste und Übertragung der Aufstellung [1, 2] | Spielerprofile, Kader, Aufstellung und eingebauter SpielPLUS-Browser | Direkte Übertragung der eigenen Aufstellung und automatischer Abgleich der offiziellen Spielberechtigungsliste nicht gefunden. |
| Kader und Spieltag | Kader, Formation, steuerbare Veröffentlichung [1] | Zusätzlich Autopilot, Wechselplanung, Liveticker und Offline-Warteschlangen | Eigenständige Stärken; daraus folgt keine belegte Überlegenheit gegenüber allen BFV-Funktionen. |
| Anwesenheit und Leistung | Anwesenheits- und Leistungsstatistik [2] | Spielminuten, Statistiken, Bewertungen, Entwicklungskurven und Entwicklungsnotizen | Statistiken sind auf beiden Seiten vorhanden. Ausbauchance: konkrete individuelle Lernziele. |
| Längere Abwesenheiten | Zeiträume und wiederkehrende Abwesenheiten laut Versionshistorie [3] | Einzelrückmeldungen, Verletzungsdaten, befristete Regeltrainings-Zusagen | Eine allgemeine Abwesenheitsplanung über mehrere Terminarten hinweg fehlt im untersuchten Code. |
| Teamkasse | Mannschaftskasse mit Strafenkatalog [1] | Aufgaben, Ausrüstung und Dienste; kein Kassenmodell gefunden | Echte Funktionslücke, für Jugendteams je nach Bedarf priorisieren. |
| Minifußball | Festivals organisieren und sich bei anderen anmelden [3, 5] | Turniere, Festival-Terminart und Regelprofile | Lokale Planung vorhanden; Teilnahme am offiziellen BFV-Festivalnetzwerk nicht gefunden. |
| Kommunikation | Push und Aufgabenverteilung sind dokumentiert [1, 2] | Mitteilungen, Direktkontakt mit Anhängen, Lesebestätigungen und Push-Einstellungen | Breite Basis; eigenständige Umfragen trotz Menübezeichnung nicht gefunden. |
| Jugend-Saisonwechsel | Neues Team je Saison und Altersklasse; kein automatisches Mitwachsen [4] | Geführter Wechsel mit Vorschau, Altersklassenwechsel, Historie und erhaltenen Elternverknüpfungen | Konkrete Differenzierungschance, wenn die Zuordnungen in der Praxis stimmen. |
| Installation | Android- und iPhone-Store-Angebot [1, 2, 3] | Dokumentierter Weg: Android-APK mit Updates, iPhone als Web-App/PWA | Einstieg für Eltern vereinfachen; eine native iOS-Store-Veröffentlichung ist hier nicht belegt. |

## Zuerst verbessern

### 1. Spieländerungen verlässlich bis zur Familie bringen

Der automatische BFV-Abgleich ist vorhanden. Im untersuchten Pfad `runBfvTeamSync → writeCompetitionMatch` werden Termine und Spielinformationen direkt gespeichert. Eine anschließende Benachrichtigung der betroffenen Familien oder Anpassung geplanter Erinnerungen ist in diesem Pfad nicht erkennbar. Das ist eine konkrete Prüfstelle mit hoher Alltagsrelevanz, kein in Produktion reproduzierter Fehler.

Gewünschtes Verhalten: Ändert sich ein Anstoß von 10:00 auf 11:00 Uhr, erhalten nur betroffene Familien eine verständliche Änderungsmeldung mit alter und neuer Zeit. Kalender und Erinnerungen passen sich an. Bei wesentlichen Änderungen kann eine erneute Rückmeldung erforderlich sein. Bereits vorhandene Rückmeldungen werden dabei nachvollziehbar behandelt.

Zusätzlich sollte der Schutz lokaler Änderungen genauer werden: Der Sync prüft zurzeit Änderungen anhand der Zeitstempel des gesamten Termins und der Spielinformationen. Eine lokale Anpassung kann dadurch auch die Übernahme unabhängiger offizieller Änderungen verhindern. Besser wäre ein Vergleich pro Feld: beispielsweise Anstoßzeit aus der Quelle übernehmen und lokalen Treffpunkt erhalten, echte Widersprüche einzeln anzeigen.

Abnahme: Zeit-, Orts- und Absageänderung sowie lokale Treffpunktänderung in einer isolierten Testumgebung durchspielen. Wiederholte Synchronisierung darf weder doppelte Termine noch doppelte Hinweise erzeugen.

Belege: `api/src/services/bfv-sync.service.ts`, `api/src/services/competition-import-write.service.ts`, `api/src/controllers/cron.controller.ts`.

### 2. Android ohne wiederkehrendes Intro sofort nutzbar machen

In `main.dart` wird das mobile Intro bei Android aktiviert. Der Videoplayer setzt die Lautstärke auf 1. Der App-Start wartet auf den Abschluss des Intros; eine reguläre Überspringen-Aktion oder eine „bereits gesehen“-Einstellung habe ich im untersuchten Pfad nicht gefunden. Die reduzierte Bewegungsdarstellung wird gesondert berücksichtigt.

Empfehlung: Video nur beim ersten Start oder freiwillig über „Über die App“, grundsätzlich überspringbar und zunächst stumm. Wer über eine Push-Nachricht kommt, soll unmittelbar zum betroffenen Termin gelangen.

Abnahme: Normalstart und Start aus einer Push-Nachricht messen. Als Zielgröße für ein festgelegtes Testgerät: der bereits angemeldete Nutzer erreicht bei einem Warmstart den nutzbaren Hauptinhalt innerhalb von etwa zwei Sekunden. Das ist ein Zielwert, kein gemessener Istwert.

Belege: `fc_teugn_app/lib/main.dart`, `fc_teugn_app/lib/app.dart`, `fc_teugn_app/lib/features/launch/animated_launch_screen.dart`.

### 3. Abwesenheiten für alle betroffenen Termine ergänzen

Beispiel: „Mein Kind ist vom 10. bis 24. Oktober nicht verfügbar“ oder „dienstags bis Weihnachten verhindert“. Das sollte vorhandene und später angelegte Trainings und Spiele berücksichtigen, auch bei mehreren Mannschaften. Einzelne Ausnahmen bleiben möglich. Erinnerungen an bereits erklärte Abwesenheiten entfallen.

Die vorhandene befristete Zusage zu Regeltrainings ist dafür ein Ansatzpunkt, deckt diesen allgemeinen Anwendungsfall aber nicht ab. Verletzungsinformationen ersetzen keine Abwesenheitsplanung.

Abnahme: Zeitraum anlegen, danach einen neuen Termin in diesem Zeitraum erzeugen und prüfen, ob Verfügbarkeit und Erinnerung richtig behandelt werden.

Beleg: `api/prisma/schema.prisma`, insbesondere `Attendance` und `RegularTrainingAttendancePreference`.

### 4. Einstieg und Bezeichnungen vereinfachen

Die öffentlich sichtbare Anmeldung wirkt konsistent und klar im Vereinsdesign. Nach „Account registrieren“ erscheint jedoch „Mitgliedschaft beantragen“. Für bestehende Vereinsmitglieder kann das wie ein neuer Vereinsbeitritt wirken. Passender: „App-Zugang beantragen“ mit einer kurzen Erklärung der Freigabe.

Als Erweiterung bietet sich eine Einladung mit vorausgewählter Mannschaft und Rolle per Link/QR-Code an. Eine Kinderzuordnung muss weiterhin verlässlich bestätigt werden; ein allgemein geteilter Link sollte sie nicht automatisch freischalten. Für die Installation: eine gemeinsame Einstiegsseite, die den passenden Weg für Android oder iPhone zeigt. Store-Veröffentlichungen können den Einstieg zusätzlich vereinfachen, sind aber ein eigenes Vorhaben.

„Nachrichten & Umfragen“ sollte zunächst „Nachrichten“ heißen oder um echte Abstimmungen ergänzt werden. Im Kommunikationsbereich finde ich Mitteilungen, Direktkontakt, Platzanfragen, Benachrichtigungen und Einstellungen, aber keine Umfrageoptionen, Stimmen oder Ergebnisansicht. Beispiel für eine sinnvolle erste Umfrage: „Saisonabschluss am Freitag oder Samstag?“ mit Frist und einer Stimme je Familie oder Kind, je nach Zweck.

Auch der Schnellzugriff „Offene Aufgaben“ im Eltern-Dashboard verdient Prüfung: Der Zähler addiert offene Rückmeldungen und Einwilligungen, führt aber zu Teamaufgaben. Zähler, Beschriftung und Ziel sollten dieselben Dinge meinen.

Belege: `fc_teugn_app/lib/features/auth/register_page.dart`, `fc_teugn_app/lib/app.dart`, `fc_teugn_app/lib/features/communications/communications_page.dart`, `fc_teugn_app/lib/features/parent/parent_dashboard_page.dart`.

## Danach die eigenen Stärken ausbauen

### Spieltags-Assistent als nächste konkrete Handlung

Familien-Assistent, Fahrgemeinschaften, Trikotdienst und Autopilot bereits zusammenführen, damit ein Trainer auf einen Blick sieht: „Zwei Rückmeldungen fehlen, ein Kind braucht eine Mitfahrt, Trikotdienst offen.“ Jede Meldung führt direkt zur passenden Handlung. Der vorhandene Autopilot prüft unter anderem Kader, Spielmodell, Ort, Treffpunkt und Positionsdaten. Die organisatorische Bereitschaft ist eine sinnvolle Erweiterung dieser bestehenden Grundlage.

Die Spielzeitplanung berücksichtigt bereits Saisonminuten. Eine neue Fairnessberechnung ist daher nicht der erste Bedarf. Wertvoller sind nachvollziehbare Begründungen und ein Vergleich von geplanter und tatsächlicher Spielzeit, aus dem der Trainer für den nächsten Spieltag lernen kann.

### „Talents“ als individuelle Entwicklung erlebbar machen

Entwicklungsnotizen, Bewertungen, Trainingspläne und eine Übungsbibliothek sind vorhanden. Darauf aufbauen: ein bis drei konkrete Lernziele pro Kind, eine passende Übung, ein vereinbarter Beobachtungszeitraum und ein kurzer Rückblick. Beispiel: „In den nächsten vier Wochen den schwächeren Fuß häufiger einsetzen.“ Fokus auf den eigenen Fortschritt und das Trainergespräch. Die bestehenden Sichtbarkeitsregeln weiterverwenden.

### Teamkasse bedarfsgerecht ergänzen

Wenn Trainer heute hierfür Excel oder Papier nutzen: Einnahmen, Ausgaben, Belege, offene Beträge, Kassenverantwortliche und Export ergänzen. Für Jugendmannschaften sind Turniergebühren, Ausflüge und Sammelzahlungen vermutlich relevanter als ein Strafenkatalog. Diese Priorität sollte ein kurzes Gespräch mit den tatsächlichen Kassenverantwortlichen bestätigen.

### Verbandsintegration gezielt ausbauen

Der größte strukturelle Vorsprung des BFV ist die unmittelbare Verbindung zum offiziellen Spielbetrieb. Ein eingebettetes SpielPLUS-Portal nimmt den App-Wechsel ab, aber überträgt nicht automatisch die in Talents geplante Aufstellung. Der nächste sinnvolle Klärungsschritt ist deshalb eine offiziell nutzbare Schnittstelle für Aufstellung und Spielberechtigungsliste. Verfügbarkeit und Freigabe sind externe Abhängigkeiten, keine rein lokale Programmieraufgabe.

Bis dahin kann eine gut lesbare, kopierbare Kaderübersicht die manuelle Arbeit erleichtern. Ein Dateiexport ist erst dann als Importhilfe zu versprechen, wenn das Zielsystem ein tatsächlich unterstütztes Format hat. Für G-/F-Jugend zusätzlich den Übergang zu offiziellen BFV-Festivaleinladungen prüfen; eine zweite isolierte Veranstalterplattform hätte für einen einzelnen Verein begrenzten Nutzen.

## Empfohlene Reihenfolge und Erfolgskriterien

| Reihenfolge | Vorhaben | Woran der Nutzen erkennbar wird |
|---|---|---|
| 1 | BFV-Änderungen, Erinnerungen und Konfliktbehandlung prüfen/verbessern | Änderungen werden verlässlich sichtbar; kein versehentliches Fahren zum alten Termin. |
| 2 | Intro, Begriffe und direkte Wege korrigieren | Eltern erledigen eine Rückmeldung ohne Hilfe und ohne vermeidbare Wartezeit. |
| 3 | Allgemeine Abwesenheiten | Ein Urlaub erfordert genau einen Eintrag je Kind. |
| 4 | Organisationshinweise im vorhandenen Assistenten | Weniger manuelle Nachfragen zu Rückmeldungen, Mitfahrten und Diensten. |
| 5 | Umfragen, Lernziele und Kasse nach Vereinsbedarf | Bisher externe Listen und Absprachen können entfallen. |
| Parallel | Offizielle Schnittstelle und Store-Vertrieb klären | Verfügbare Zugänge, unterstützte Prozesse und Aufwand sind konkret bekannt. |

Für die Aussage „besser als die BFV-Team-App“ empfehle ich einen Vergleich mit zwei Trainern und fünf Eltern, darunter eine Familie mit mehreren Kindern und Nutzer beider Mobilplattformen. Gleiche Aufgaben in beiden Apps: Zugang erhalten, Training beantworten, Urlaub eintragen, Spielverlegung verstehen und nächsten Spieltag vorbereiten. Messen: benötigte Zeit, Hilfebedarf, Fehler und notwendige Rückfragen außerhalb der App. Ergänzend Offline-Speicherung und Push-Verhalten auf echten Geräten prüfen. Die hier genannten Ziele sind noch nicht erhobene Messwerte.

Die App wurde bei dieser Analyse nicht verändert. Es wurden keine produktiven Nachrichten versendet und keine Tests gegen die Produktivdatenbank ausgeführt.

## Öffentliche Quellen

1. [BFV: Die BFV-Team-App – Funktionen und FAQ](https://www.bfv.de/der-bfv/digitalangebote/bfv-team-app/die-bfv-team-app) – Grundlage für die entsprechenden Matrixzeilen und die Einordnung der SpielPLUS-Anbindung.
2. [BFV-Team-App bei Google Play](https://play.google.com/store/apps/details?hl=de&id=de.bfv.teamapp.android) – offizielle Beschreibung zu Spielerlisten, Statistik und Aufgaben; beim Abruf Aktualisierung vom 17. August 2026.
3. [BFV-Team-App im Apple App Store](https://apps.apple.com/de/app/bfv-team-app/id1403863269) – insbesondere Versionshistorie zu längeren und wiederkehrenden Abwesenheiten sowie Minifußball.
4. [BFV: Saisonwechsel 2026/27](https://www.bfv.de/news/servicethemen/2026/06/saisonubergang-bfv-team-app) – aktuelle Erklärung der Jugendmannschaften beim Saisonwechsel.
5. [BFV: Organisation von Minifußball- und Hallenfestivals](https://www.bfv.de/news/servicethemen/2024/12/reibungslose-organisation-von-minifussball--und-hallenfestivals) – offizielle Festivalabläufe.

Die öffentlichen Quellen stützen die BFV-Angaben. Empfehlungen und Prioritäten sind aus dem untersuchten FC-Teugn-Code und den beschriebenen Alltagsszenarien abgeleitete Einschätzungen.
