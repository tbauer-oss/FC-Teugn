# Datenschutzrechtlicher Prüfbericht – FC Teugn Talents

**Prüfstand:** 11. August 2026
**Geprüfter Ausgangsstand:** Commit `662f248`, Branch `main`
**Technischer Nachprüfungsstand:** Release `1.5.73+92`
**Prüfgegenstand:** Flutter-App, Web-App, Node/Express-API, Prisma-Datenmodell, mobile Offline-Speicherung, Push-Kommunikation, BfV-Einbindung und öffentlich erreichbare Produktionsendpunkte

## 1. Ergebnis in einem Satz

Die App enthält bereits mehrere gute Datenschutz- und Sicherheitsmechanismen, ist in der derzeit geprüften Fassung aber **noch nicht belastbar als vollständig DSGVO-konform freigabefähig**. Vor einer breiten Nutzung durch Eltern und Kinder müssen insbesondere die Datenschutz-Folgenabschätzung, die vollständige Information bei der Registrierung, die technische Durchsetzung von Einwilligungen und Widerrufen, das Lösch- und Aufbewahrungskonzept, die Dienstleister-/Drittlanddokumentation sowie mehrere konkrete Sicherheitslücken geschlossen oder verbindlich nachgewiesen werden.

## 2. Wichtiger rechtlicher Hinweis

Dieser Bericht ist eine umfassende technische und organisatorische Datenschutzprüfung des vorhandenen Quellcodes und der von außen prüfbaren Produktionskonfiguration. Eine „100-prozentige“ rechtsverbindliche Freigabe kann weder durch eine Quellcodeprüfung noch durch ein KI-System erteilt werden. Sie setzt zusätzlich mindestens voraus:

- Prüfung der tatsächlichen Vereinsabläufe, Verträge, Berechtigungskonzepte und verwendeten Produktionskonten;
- Prüfung aller Auftragsverarbeitungsverträge, Unterauftragsverarbeiter, Regionen und Drittlandgarantien;
- dokumentierte Datenschutz-Folgenabschätzung und Rechtsgrundlagenentscheidung;
- Prüfung durch den zuständigen Datenschutzbeauftragten oder einen spezialisierten Rechtsanwalt;
- regelmäßige Wiederholungsprüfung nach Änderungen.

Die hier festgestellten technischen Tatsachen sind belastbar für den geprüften Quellstand. Rechtliche Wertungen und empfohlene Fristen müssen vom Verantwortlichen verbindlich beschlossen und juristisch bestätigt werden.

## 2.1 Technische Nachprüfung nach Umsetzung der Sofortmaßnahmen

Die nachfolgend beschriebenen Befunde dokumentieren den Ausgangsstand. Für Release `1.5.73+92` wurden die unmittelbar im Quellcode lösbaren Kernmaßnahmen anschließend umgesetzt und automatisiert geprüft:

- produktiver Startabbruch bei fehlenden, zu kurzen oder mehrfach verwendeten Token-Geheimnissen;
- getrennte Access-, Refresh-, Medien- und Notfalltoken sowie zentrale Tokenprüfung;
- globale private `no-store`-Antworten und zentrale Browser-/API-Sicherheitsheader;
- strukturierte, reduzierte Fehlerprotokolle ohne rohe Fehler- oder Inhaltsausgabe;
- Datenschutzinformation, Vertragszustimmung und optionale Einwilligung werden technisch als unterschiedliche Nachweisarten gespeichert;
- zentraler, signatur-, zweck-, laufzeit- und widerrufsabhängiger Zugriffsschutz für Fotos, Mannschaftsfotos und medizinische Daten;
- der alte Einwilligungsweg kann keine unbelegten Freigaben oder undokumentierten Widerrufe mehr erzeugen;
- Passwort-Reset-Geheimnisse werden nicht mehr in Push- oder Benachrichtigungsdaten gespeichert; der einmalige Austausch ist an ein bereits registriertes aktives Gerät gebunden;
- Pushvorschauen auf dem Sperrbildschirm sind inhaltsarm, während die Detailinformation geschützt in der App verbleibt;
- die vier hohen produktiven Abhängigkeitsbefunde werden durch getestete, versionsgebundene Transitiv-Overrides geschlossen; der erneute Produktionsaudit meldet keine hohe oder kritische Schwachstelle;
- Auskunft, Datenübertragbarkeit, Berichtigung, Einschränkung, Widerspruch, Widerruf und Löschung besitzen nachvollziehbare Antragsprozesse;
- der Datenexport umfasst nun zusätzlich Geräte, Support, Fahrgemeinschaften, Aufgaben, Ausrüstung, Tickerbeiträge und Dateimetadaten;
- die Kontoanonymisierung schützt das letzte Systemadministrationskonto und bereinigt weitere operative Zuordnungen, Supportanhänge und lokale Sitzungsdaten;
- ein konservativer serverseitiger Aufbewahrungsjob entfernt abgelaufene Reset-/Sitzungsreste, Idempotenzdaten, alte Benachrichtigungen und inaktive Pushgeräte, ohne Vereins-, Audit- oder Einwilligungsnachweise pauschal zu löschen;
- Android-Cloud-/Gerätebackups sind ausgeschlossen; Offline-Warteschlangen und Liveticker-Caches werden beim Abmelden benutzerspezifisch gelöscht und der Ticker-Cache ist auf 48 Stunden begrenzt.

Die Nachprüfung bestand aus Prisma-Schemavalidierung, TypeScript-Build, Produktions-Abhängigkeitsaudit ohne hohe oder kritische Meldung, 151 Backend-Regressionstests, Flutter-Analyse ohne Befund und 338 Flutter-/UI-Regressionstests. Damit sind die genannten technischen Sofortbefunde geschlossen beziehungsweise erheblich reduziert. Offen bleiben insbesondere die organisatorischen und rechtlich verbindlich zu beschließenden Punkte: DSFA, Verzeichnis der Verarbeitungstätigkeiten, Rechtsgrundlagen-/Fristenfreigabe, AV-Verträge und Drittlandprüfung, Incident-Prozess, Backup-Löschfristen der Anbieter, MFA beziehungsweise zentraler Missbrauchsschutz sowie eine unabhängige juristische und sicherheitstechnische Endprüfung.

## 3. Prüfungsumfang und Methode

Geprüft wurden:

1. Datenmodell und Migrationen mit sämtlichen erkennbaren personenbezogenen Datenkategorien.
2. Registrierung, Anmeldung, Sitzungen, Passwortzurücksetzung und Berechtigungen.
3. Spieler-, Eltern-, Trainer- und Funktionärsdaten einschließlich Gesundheitsdaten Minderjähriger.
4. Einwilligungen, Widerrufe, Nachweise, Fotos, Dokumente und private Dateien.
5. Termine, Anwesenheiten, Zu-/Absagen, Gründe, Fahrgemeinschaften, Kader, Aufstellung, Liveticker, Bewertungen und Leistungsdaten.
6. Nachrichten, Support, Benachrichtigungen und Push-Versand.
7. Auskunft, Export, Löschung und Datenschutzanfragen.
8. Offline-Speicherung auf Mobilgeräten, Update-Verteilung und Gerätesicherheit.
9. Vercel-, Neon-, Firebase- und BfV-Berührungspunkte.
10. Produktionsprüfung ohne Anmeldung: HTTPS, Header, CORS und Cache-Verhalten.
11. Audit der produktiven JavaScript-Abhängigkeiten.

Nicht geprüft werden konnten:

- Produktionsdaten, Umgebungsvariablen oder tatsächliche Geheimnisse;
- unterschriebene Verträge und deren aktuelle Anhänge;
- interne Arbeitsanweisungen, Berechtigungsfreigaben und reale Zugriffsprotokolle;
- Wiederherstellbarkeit, Backups und Löschung beim jeweiligen Cloud-Anbieter;
- vollständiger Penetrationstest, Quellcodeanalyse der Cloud-Anbieter oder Endgeräteforensik;
- vereinsregisterrechtliche Zusatzangaben; Anschrift und Vertretung wurden ergänzend mit dem offiziellen Vereinsimpressum abgeglichen.

## 4. Schutzbedarf und besondere Risikolage

Die App verarbeitet nicht nur normale Vereinsdaten. Sie bündelt mehrere besonders risikoreiche Konstellationen:

- Daten von Kindern und Jugendlichen als besonders schutzbedürftige Personen;
- Gesundheitsdaten nach Art. 9 DSGVO, etwa Allergien, Medikamente, Erkrankungen, Arztkontakte und Notfallhinweise;
- Fotos, Ausweisdaten, Passnummern und unterschriftsähnliche Rohdaten;
- Anwesenheiten, Absagegründe, Leistungsbewertungen und Entwicklungsbeobachtungen;
- Aufenthaltsorte, Termine, Treffpunkte, Fahrgemeinschaften und Kaderinformationen;
- Eltern-Kind-Beziehungen, Nachrichten, Supportinhalte und Gerätekennungen;
- systematische Bewertung von Spielern über eine Saison hinweg.

Aus dieser Kombination ergibt sich ein **hoher Schutzbedarf**. Eine Datenschutz-Folgenabschätzung nach Art. 35 DSGVO ist nach der vorliegenden Risikolage sehr wahrscheinlich erforderlich und sollte vor der breiten Einführung abgeschlossen werden.

### 4.1 Technisches Verarbeitungsinventar

| Bereich | Erkennbare Daten | Betroffene Personen |
|---|---|---|
| Konto und Anmeldung | Name, E-Mail, Telefon, Passwort-Hash, Rolle, Status, Sitzungen, IP-Adresse, User-Agent, Reset- und Refresh-Token-Metadaten | alle Nutzer |
| Registrierung/Freigabe | gewünschte Jugend/Mannschaft/Rolle, Kindname, Beziehung, Nachrichten, Adminnotizen, Einwilligungs-/Kenntnisnahmezeitpunkte | Antragsteller, Kinder |
| Spielerprofil | Name, Rufname, Geburtsdatum, Geschlecht, Nationalität, Position, Trikot-/Passnummer, Vereinsbeitritt, Foto, Status | überwiegend Minderjährige |
| Familie | Eltern-Kind-Verknüpfungen, Beziehung, Sorge-/Vertretungsinformationen | Eltern, Kinder |
| Gesundheit/Notfall | Allergien, Medikamente, Erkrankungen, Arztname/-telefon, Notfallnotizen und Notfallkontakte | Spieler, Kontaktpersonen |
| Einwilligungen | Zweck/Typ, Status, Version, Sorgeberechtigtenangabe, Signaturzüge, Dokument-Hash, Widerruf, Nachweise | Eltern, Kinder, Unterzeichner |
| Termine und Teilnahme | Zeit, Ort, Adresse, Treffpunkt, Mannschaften, individuelle Teilnehmer, Zu-/Absage/Vielleicht, Gründe, Trainerkorrekturen | Spieler, Eltern, Trainer |
| Fahrgemeinschaften | Anbieter, benötigte/angebotene Plätze, Mitfahrer, Treffpunkt | Eltern, Spieler, Trainer |
| Spielbetrieb | Kader, Aufstellung, Einsatzzeit, Position, Tore, Vorlagen, Kommentare, Tickerverlauf, Taktik | Spieler, Trainer |
| Entwicklung | Beobachtungen, Trainerbewertungen, Saisondurchschnitt, interne Leistungsdaten | Spieler, Trainer |
| Kommunikation | Nachrichten, Ankündigungen, Anhänge, Empfänger, Lesebestätigungen, Supporttickets | alle Nutzer |
| Geräte/Push | Push-Token/Endpoint, Plattform, Gerät, Zustellergebnisse, Fehler, Aktionsziel | App-Nutzer |
| Dateien | Originalname, Typ, Größe, Prüfsumme, Speicherpfad, Uploader, Eigentümer, Löschstatus, Fotos/Dokumente | Spieler, Eltern, Trainer |
| Sicherheit/Audit | Aktion, Akteur, Zielobjekt, Metadaten, Zeitstempel, technische Fehler | Nutzer, Administratoren |
| Externe Sportdaten | BfV-Kennung, BfV-/iCal-URL, externe Referenzen, Spiele/Gegner | Mannschaften, indirekt Spieler/Trainer |

Primäre technische Speicherorte sind die Neon-PostgreSQL-Datenbank, private Objekte in Vercel Blob, die lokale verschlüsselte Gerätespeicherung sowie Firebase/Google im Rahmen des Push-Versands. BfV-Inhalte werden nach Zustimmung extern geladen. Diese Zuordnung ist durch die tatsächlichen Produktionskonten und Regionen zu bestätigen.

## 5. Gesamtbewertung nach Themen

| Prüfgebiet | Bewertung | Kurzbegründung |
|---|---:|---|
| Rechtmäßigkeit und Zweckbindung, Art. 5/6/9 | Rot | Rechtsgrundlagen sind zu pauschal; Gesundheits-, Foto- und Leistungsdaten brauchen getrennte Entscheidungen und technische Durchsetzung. |
| Information, Art. 12–14 | Rot | Die bei der Registrierung bestätigte Datenschutzinformation ist unvollständig. Die ausführlichere App-Seite bleibt zu allgemein. |
| Betroffenenrechte, Art. 15–22 | Gelb/Rot | Export und Löschantrag existieren, sind aber unvollständig; Berichtigung, Einschränkung, Widerspruch und Portabilität fehlen als vollständige Prozesse. |
| Datenschutz durch Technikgestaltung, Art. 25 | Gelb | Gute Ansätze vorhanden, aber Einwilligungen, Widerrufe, Cache, Push und Backups sind nicht durchgängig „privacy by default“. |
| Auftragsverarbeitung, Art. 28 | Rot, nicht nachgewiesen | Technische Anbieter sind erkennbar; unterschriebene AV-Verträge, Regionen, Weisungen und Löschregeln sind nicht im Prüfmaterial nachgewiesen. |
| Verzeichnis von Verarbeitungstätigkeiten, Art. 30 | Rot, nicht nachgewiesen | Kein vollständiges, verabschiedetes Verzeichnis mit Zwecken, Rechtsgrundlagen, Empfängern und Fristen vorgelegt. |
| Sicherheit, Art. 32 | Gelb/Rot | Mehrere gute Kontrollen, aber kritische Konfigurations-, Abhängigkeits-, Cache-, Token- und Rate-Limit-Befunde. |
| Datenschutzverletzungen, Art. 33/34 | Rot, nicht nachgewiesen | Kein vollständiger Incident-Response-Prozess mit 72-Stunden-Entscheidung, Register und Benachrichtigungsvorlagen vorgelegt. |
| Datenschutz-Folgenabschätzung, Art. 35 | Rot | Für die konkrete Verarbeitung nicht vorgelegt; wegen Kinder-, Gesundheits- und Bewertungsdaten dringend erforderlich. |
| Drittlandübermittlung, Art. 44–49 | Rot, nicht nachgewiesen | Firebase/Google und möglicherweise weitere Anbieter erfordern eine dokumentierte Transferprüfung und transparente Information. |
| TDDDG § 25 / Endgerätezugriff | Gelb | BfV-Einwilligung ist ein guter Ansatz; Widerruf und vollständige Endgeräte-/SDK-Inventur fehlen. |

## 6. Positiv festgestellte Maßnahmen

Folgende Punkte sind bereits gut angelegt und sollten beibehalten werden:

- HTTPS und HSTS sind auf der Produktions-Webseite aktiv.
- Die API erlaubt produktiv nur die konfigurierte Web-Herkunft; eine fremde Test-Origin erhielt keine CORS-Freigabe.
- Access-Tokens sind kurzlebig; Refresh-Tokens werden gehasht, rotiert und auf Wiederverwendung geprüft.
- Mobile Anmeldedaten und Offline-Warteschlangen werden über `FlutterSecureStorage` gespeichert.
- Allgemeine Offline-Aufträge werden auf 14 Tage, Liveticker-Aufträge und Liveticker-Cache auf 48 Stunden begrenzt und beim Abmelden benutzerspezifisch entfernt.
- Private Spielerdateien werden über signierte Zugriffe statt öffentliche Dauer-URLs bereitgestellt.
- Notfallzugriffe auf Gesundheitsinformationen verlangen Berechtigung und erneute Authentisierung beziehungsweise einen kurzlebigen Notfallzugriff.
- Rollen-, Mannschafts- und Berechtigungsprüfungen sind an vielen Endpunkten vorhanden.
- Ein neuerer Einwilligungsprozess unterstützt Sorgeberechtigtennachweis, Versionierung, Dokument-Hash, Signatur und Widerruf.
- Audit-Logs, Push-Geräteverwaltung und Deaktivierung ungültiger Tokens sind grundsätzlich vorhanden.
- Für das BfV-Widget wird vor dem Laden eine Einwilligung abgefragt.
- Es wurden keine Werbetracker oder klassischen Marketing-Analytics-SDKs im geprüften Quellstand gefunden.

Diese Maßnahmen reichen allein noch nicht für die Freigabe, bilden aber eine brauchbare Grundlage.

## 7. Kritische Befunde – vor breiter Einführung zu schließen

### P0-1: Datenschutz-Folgenabschätzung, Verarbeitungsverzeichnis und Datenschutzbeauftragten-Entscheidung fehlen als Nachweis

**Risiko:** Sehr hoch
**Rechtsbezug:** Art. 5 Abs. 2, 24, 30, 35 DSGVO; § 38 BDSG

Die App verarbeitet Gesundheitsdaten Minderjähriger, umfangreiche Verhaltens-/Anwesenheitsdaten und interne Leistungsbewertungen. Das ist eine Verarbeitung mit hohem Risiko. Die Kombination spricht stark für eine verpflichtende Datenschutz-Folgenabschätzung. Falls eine DSFA erforderlich ist, kann nach § 38 BDSG unabhängig von der Beschäftigtenzahl eine Pflicht zur Benennung eines Datenschutzbeauftragten entstehen.

**Erforderlich:**

1. Vollständiges Verzeichnis der Verarbeitungstätigkeiten erstellen.
2. DSFA mit Verarbeitungsszenarien, Erforderlichkeit, Verhältnismäßigkeit, Risiken, Maßnahmen und Restrisiko durchführen.
3. Entscheidung zur Benennung eines Datenschutzbeauftragten dokumentieren.
4. Bei verbleibendem hohen Restrisiko vor Start die zuständige Aufsichtsbehörde konsultieren.

### P0-2: Datenschutzinformation bei der Registrierung ist unvollständig und wird fälschlich als Einwilligung behandelt

**Risiko:** Sehr hoch
**Rechtsbezug:** Art. 5 Abs. 1 lit. a, 6, 7, 12, 13 DSGVO

Die initiale Datenbankmigration hinterlegt als Datenschutzinformation nur einen einzelnen allgemeinen Satz. Die Registrierung verlangt dessen Bestätigung und speichert sie als erteilte Einwilligung. Eine Datenschutzinformation ist jedoch grundsätzlich eine Informationspflicht, keine pauschale Rechtsgrundlage für sämtliche Verarbeitungen.

**Nachweise im Quellstand:**

- `api/prisma/migrations/20260729033000_professional_registration_approval/migration.sql:119`
- `api/src/controllers/auth.controller.ts` im Registrierungsprozess
- `fc_teugn_app/lib/features/auth/register_page.dart` bei der Checkbox-Darstellung

**Erforderlich:**

1. Vollständige, versionierte Art.-13-Information direkt vor Absendung der Registrierung anzeigen oder dauerhaft verlinken.
2. Bestätigung als „zur Kenntnis genommen“ protokollieren, nicht als pauschale Einwilligung.
3. Einwilligungen nur getrennt, freiwillig, konkret und widerrufbar abfragen, beispielsweise Fotos, optionale Pushs oder Gesundheitsdaten.
4. Alte Versionen unveränderlich archivieren und bei wesentlichen Änderungen erneut informieren.

### P0-3: Einwilligungen und Widerrufe werden technisch nicht durchgängig erzwungen

**Risiko:** Sehr hoch
**Rechtsbezug:** Art. 5 Abs. 1 lit. a/b/c, 6, 7, 9 und 25 DSGVO

Neben dem neuen, beweissicheren Einwilligungsprozess existiert weiterhin ein älterer Endpunkt, über den berechtigte Trainer/Funktionäre einen Einwilligungsstatus setzen können, ohne die Nachweise des neuen Prozesses zu erzwingen. Außerdem werden medizinische Profile und Spielerfotos nicht an jeder Lese-, Schreib- und Auslieferungsstelle gegen den aktuellen Einwilligungs-/Widerrufsstatus geprüft.

**Nachweise:**

- `api/src/routes/players.routes.ts:70`
- `api/src/controllers/players.controller.ts:709–880`
- `api/src/controllers/player-consents.controller.ts`
- `api/src/controllers/player-files.controller.ts`

**Auswirkung:** Ein Widerruf kann in der Datenbank stehen, während Gesundheitsdaten oder Fotos weiterhin verarbeitet beziehungsweise ausgeliefert werden. Das ist ein wesentliches Freigabehindernis.

**Erforderlich:**

1. Legacy-Endpunkt entfernen oder ausschließlich auf den beweissicheren Prozess umstellen.
2. Zentralen Policy-Enforcer für `PHOTO`, `TEAM_PHOTO`, `MEDICAL_DATA`, `TRANSPORT` und `COMMUNICATION` einführen.
3. Bei Widerruf sofort Auslieferung und weitere Verarbeitung sperren; anschließend fristgerecht löschen beziehungsweise rechtmäßig notwendige Nachweise getrennt sperren.
4. Fotozwecke und Veröffentlichungskanäle getrennt verwalten: interne Profilanzeige, Mannschaftsfoto, Webseite, soziale Medien, Presse.
5. Gesundheitsdaten nicht allein auf eine pauschale Einwilligung stützen; Art. 6 und Art. 9 jeweils getrennt dokumentieren.

### P0-4: Kein vollständiges, technisch durchgesetztes Lösch- und Aufbewahrungskonzept

**Risiko:** Sehr hoch
**Rechtsbezug:** Art. 5 Abs. 1 lit. c/e, 17, 25 und 32 DSGVO

Im Quellstand ist kein vollständiger Lebenszyklus für Registrierungsanfragen, Gesundheitsdaten, Absagegründe, Leistungsbewertungen, Nachrichten, Support, Push-Tokens, Audit-Logs, Dateien, Offline-Daten und Backups erkennbar. Der bestehende Löschprozess anonymisiert Teile eines Kontos, umfasst aber nicht nachweisbar alle Inhalte und löscht gespeicherte Blob-Dateien nicht zuverlässig vollständig.

**Nachweise:**

- `api/src/controllers/privacy.controller.ts:235–430`
- `api/src/controllers/player-files.controller.ts:133, 171, 309`
- `api/prisma/schema.prisma`

**Erforderlich:**

1. Datenkategorien mit Zweck, Startpunkt der Frist, Aufbewahrung, Löschmethode, Backup-Frist und Rechtsausnahme festlegen.
2. Automatisierte Löschjobs mit Protokoll, Wiederholungslogik und Alarm bei Fehlern bauen.
3. Objektdatei und Datenbankmetadaten gemeinsam transaktional beziehungsweise über eine zuverlässige Löschwarteschlange entfernen.
4. Freitexte und Autorenbezüge in Nachrichten, Support, Bewertungen, Trainingsplänen, Aufgaben und Audits einbeziehen.
5. Löschsperren nur dokumentiert für konkrete Rechtsansprüche oder gesetzliche Pflichten verwenden.

### P0-5: Auftragsverarbeiter, Unterauftragsverarbeiter und Drittlandtransfers sind nicht vollständig nachgewiesen

**Risiko:** Sehr hoch
**Rechtsbezug:** Art. 13, 28, 32 und 44–49 DSGVO

Technisch erkennbar sind mindestens Vercel (Hosting/API/Dateien), Neon (PostgreSQL), Google/Firebase Cloud Messaging und BfV-Inhalte. Firebase weist für FCM auf globale Datenverarbeitung hin. Im Prüfmaterial fehlen die unterschriebenen AV-Verträge, konkrete Regionen, Unterauftragsverarbeiter, Löschregeln, Transfermechanismen und Transfer-Risikoabwägungen.

**Erforderlich je Anbieter:**

- Rolle bestimmen: Auftragsverarbeiter, gemeinsam Verantwortlicher oder eigener Verantwortlicher.
- Aktuellen AV-Vertrag und technische/organisatorische Maßnahmen archivieren.
- Hosting-/Speicherregion und Supportzugriffe dokumentieren.
- Unterauftragsverarbeiter und Änderungsbenachrichtigungen prüfen.
- Für Drittländer Angemessenheitsbeschluss oder Standardvertragsklauseln plus Transferprüfung dokumentieren.
- Löschung, Rückgabe, Backup-Zyklus, Incident-SLA und Auditmöglichkeiten festlegen.
- Anbieter, Empfängerkategorie, Land und Garantie transparent in der Datenschutzinformation nennen.

### P0-6: Sicherheitskonfiguration kann bei fehlenden Geheimnissen mit unsicheren Standardwerten starten

**Risiko:** Sehr hoch
**Rechtsbezug:** Art. 25 und 32 DSGVO

`api/src/lib/jwt.ts:4–5` verwendet bei fehlenden Umgebungsvariablen die festen Werte `access_secret` und `refresh_secret`. Der Produktionsprozess muss stattdessen abbrechen, sobald Geheimnisse fehlen, zu kurz sind oder identisch verwendet werden.

**Erforderlich:**

- Startabbruch bei fehlenden/schwachen Secrets;
- getrennte zufällige Schlüssel für Access, Refresh, Medien und Notfallzugriffe;
- Rotation, Versionierung und dokumentierte Notfallrotation;
- keine Geheimnisse in Logs, Builds oder Client-Konfigurationen;
- MFA für Systemadministration und Vereinsleitung.

### P0-7: Passwort-Reset-Geheimnis wird in Push-/Benachrichtigungsdaten gespeichert und weitergegeben

**Risiko:** Sehr hoch
**Rechtsbezug:** Art. 25 und 32 DSGVO

Der rohe Reset-Token wird in eine `actionUrl` eingebettet, als Benachrichtigung gespeichert und über Push weitergereicht (`api/src/controllers/auth.controller.ts:557`; ebenfalls Admin-Reset). Damit kann ein Reset-Geheimnis in Datenbank, Push-Anbieter, Gerätespeicher, Logs oder Backups gelangen.

**Erforderlich:**

1. Rohes Reset-Geheimnis niemals in Benachrichtigungen oder Push-Payloads speichern.
2. Nur einen kurzlebigen, einmaligen und geräte-/vorgangsgebundenen Austauschcode versenden.
3. Reset nach Nutzung, Ablauf, Passwortänderung und Kontosperre sofort invalidieren.
4. Benachrichtigungstext ohne sensible Kontodetails; sicherheitsrelevante Ereignisse zusätzlich protokollieren.

### P0-8: Produktive Abhängigkeiten enthalten bekannte Schwachstellen

**Risiko:** Hoch bis sehr hoch
**Rechtsbezug:** Art. 25 und 32 DSGVO

Der reproduzierte Produktionsaudit meldete am 11.08.2026 **0 kritische, 4 hohe, 2 mittlere und 2 niedrige** Schwachstellen. Betroffen sind unter anderem `path-to-regexp`, `defu`, `effect`, `brace-expansion`, `qs`, `uuid` und `body-parser`. Nicht jede transitive Meldung ist automatisch ausnutzbar; insbesondere der Laufzeitpfad von `path-to-regexp` und die tatsächlich eingesetzten Prisma/Firebase-Pfade müssen aber unverzüglich bewertet werden.

**Erforderlich:** Lockfile aktualisieren, Breaking Changes testen, erneuten Produktionsaudit durchführen, Erreichbarkeit dokumentieren und ein regelmäßiges Patch-/SBOM-Verfahren einführen.

## 8. Hohe Befunde – kurzfristig zu schließen

### P1-1: Datenexport und Betroffenenrechte sind unvollständig

Der Export umfasst viele Stammdaten, Einwilligungen und verknüpfte Kinderdaten, lässt aber unter anderem Supporttickets, Nachrichteninhalte, Lesebestätigungen, Fahrgemeinschaften, Pushgeräte/-zustellungen, Bewertungen, Dateien, Aufgaben, Berechtigungsabweichungen und vollständige Verarbeitungsmetadaten aus. Außerdem gibt es keinen vollständigen Workflow für Zugang/Auskunft, Berichtigung, Einschränkung, Widerspruch und Portabilität.

**Maßnahmen:** Zentraler Art.-12-bis-22-Prozess, Identitätsprüfung, Fristenüberwachung, begründete Entscheidungen, Drittpersonen-Schwärzung, maschinenlesbarer Export und `Cache-Control: private, no-store`.

### P1-2: Zugriff auf Gesundheitsdaten ist rollenmäßig zu breit

Trainer und mehrere Funktionsrollen erhalten grundsätzlich `VIEW_SENSITIVE_PLAYER`; Trainer teilweise auch `MANAGE_SENSITIVE_PLAYER`. Für Gesundheitsdaten ist ein strengerer Need-to-know-Ansatz erforderlich.

**Maßnahmen:** Zugriff nur für konkret betreute Mannschaft, aktiven Termin/Kader und begrenzten Zeitraum; erneute Authentisierung; keine Gesundheitsdaten in Listen; detailliertes Audit; sofortiger Entzug bei Rollenwechsel; regelmäßige Berechtigungsrezertifizierung.

### P1-3: Push-Nachrichten enthalten zu viele Inhaltsdaten

Titel, Nachrichtentext und Ziel-URL werden über Firebase übertragen. Push-Inhalte können auf einem gesperrten Gerät sichtbar sein. Gesundheitsdaten, Absagegründe, Bewertungen und detaillierte Kinderdaten dürfen dort nie erscheinen.

**Maßnahmen:** Standardmäßig generische Mitteilung „Neue Information in der App“, Inhalt nach Anmeldung abrufen, individuelle Vorschauoption, deduplizierte Tokens, kurze Token-Aufbewahrung, genaue Empfängerprüfung.

### P1-4: Private Dateien brauchen härtere Lebenszyklus- und Uploadkontrollen

MIME-Listen reichen nicht gegen manipulierte oder schädliche Dateien. Signierte URLs sind teils lang gültig und können in Verlauf, Referrer oder Logs gelangen. Löschfehler beim Objektspeicher werden nicht zuverlässig nachgearbeitet.

**Maßnahmen:** Magic-Byte-Prüfung, Malware-Scan, Größen-/Bilddekodierung, Metadatenbereinigung, kurze URLs oder authentisiertes Streaming, `no-store`/`no-referrer`, zuverlässige Löschwarteschlange und Orphan-Scan.

### P1-5: Mobile Backups und Offline-Daten sind nicht vollständig abgesichert

Die Offline-Warteschlangen werden verschlüsselt gespeichert und zeitlich begrenzt. Im Android-Manifest fehlen jedoch explizite Backup-Ausschlüsse beziehungsweise Datenextraktionsregeln. Somit muss ausgeschlossen werden, dass sensible Offline-Aufträge, Sitzungen oder Update-Dateien in Cloud-/Gerätebackups gelangen.

**Maßnahmen:** Android-Backupregeln, iOS-Keychain-/Backupklassifizierung, minimale Offline-Payloads, sofortige Löschung nach Versand/Logout, Remote-Sitzungswiderruf, Inaktivitätsablauf und Schutz vor Screenshots in hochsensiblen Ansichten.

### P1-6: Cache- und Browser-Sicherheitsheader sind unzureichend

Unauthentisierte API-Fehlerantworten wurden mit `Cache-Control: public` ausgeliefert; ein globaler Nachweis für `private, no-store` bei authentifizierten Inhalten fehlt. Die Web-App hatte HSTS, aber keine belastbare CSP, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy` oder Frame-Schutzrichtlinie.

**Maßnahmen:** Global `private, no-store` für Auth-/API-Daten, gezielte öffentliche Ausnahmen; CSP mit Nonces; `nosniff`; strenge Referrer- und Permissions-Policy; `frame-ancestors`; sichere Cross-Origin-Richtlinien.

### P1-7: Rate-Limiting, Protokollierung und Administratorenschutz reichen für den Schutzbedarf nicht

Das Rate-Limiting ist instanzlokal und deshalb in einer serverlosen Umgebung uneinheitlich. Der globale Fehlerhandler protokolliert rohe Fehlerobjekte. Ein verbindliches Redaktions-/Aufbewahrungskonzept für Logs ist nicht erkennbar.

**Maßnahmen:** Zentraler Rate-Limit-Store oder WAF, konto- und IP-basierte progressive Verzögerung, Schutz vor Credential Stuffing, MFA für privilegierte Rollen, strukturierte redigierte Logs, begrenzte Aufbewahrung und Alarme.

### P1-8: Incident-Response- und Meldeprozess ist nicht nachgewiesen

**Maßnahmen:** Verantwortlichkeiten, 24/7-Eskalation, internes Vorfallregister, 72-Stunden-Entscheidung, Risikobewertung, Behörden- und Betroffenenvorlagen, Sicherung von Beweisen, Anbieter-SLA, Wiederanlauf- und Übungskonzept.

## 9. Weitere relevante Befunde

### Controller-Angaben verifizieren

Die App nennt `FC Teugn e.V.`, `Kreutweg 14, 93356 Teugn` und `info@fc-teugn.de`. Anschrift und Vertretung durch Florian Christl wurden mit dem offiziellen Vereinsimpressum abgeglichen. Registergericht und Registernummer sind vor der finalen juristischen Freigabe zusätzlich anhand des Vereinsregisters zu bestätigen.

### Minderjährigenschutz

Art. 8 DSGVO gilt nicht pauschal für jede Vereinsverarbeitung, sondern insbesondere bei einwilligungsbasierten Diensten der Informationsgesellschaft, die einem Kind direkt angeboten werden. Unabhängig davon sind elterliche Vertretungsbefugnis, Reifegrad, Kindeswohl und kindgerechte Informationen zu berücksichtigen. Eltern dürfen nicht automatisch alle sensiblen Inhalte eines Jugendlichen sehen, wenn Rechte oder Wohl des Kindes entgegenstehen.

### BfV-Widget und TDDDG

Das vorgeschaltete Einwilligungsfenster ist positiv. Es fehlt jedoch eine gleich leicht erreichbare Möglichkeit, die Entscheidung zurückzunehmen und gespeicherte Widget-/Endgerätedaten zu löschen. BfV ist voraussichtlich für seine Widgetverarbeitung eigener Verantwortlicher; Rolle und Datenflüsse müssen verbindlich geprüft und transparent beschrieben werden.

### Öffentliche Kalenderabonnements

Kalenderfeeds werden durch lange zufällige Tokens geschützt und lassen sich durch Rotation erneuern. Es sollte zusätzlich eine explizite Widerrufsfunktion geben. Titel, Beschreibung und Ort müssen minimiert werden, weil Kalenderanbieter den geheimen Link und die enthaltenen Daten erhalten können.

### Automatisierte Entscheidungen

Der Autopilot und das Leistungszentrum dürfen nicht zu ausschließlich automatisierten Entscheidungen mit erheblicher Wirkung führen. Trainer müssen Vorschläge nachvollziehen, korrigieren und verantworten. Bewertungslogik, Datenquellen, Speicherfrist, Sichtbarkeit und Widerspruchs-/Korrekturmöglichkeit sind transparent zu dokumentieren.

## 10. Empfohlene Rechtsgrundlagenmatrix

Die endgültige Festlegung muss der Verein je Verarbeitung dokumentieren. Folgende Zuordnung ist als Arbeitsgrundlage geeignet:

| Verarbeitung | Mögliche Grundlage | Zusätzliche Bedingung |
|---|---|---|
| Konto, Mitgliedschaft, Mannschaftszuordnung | Art. 6 Abs. 1 lit. b oder f | Vertrag/mitgliedschaftliche Beziehung oder dokumentierte Interessenabwägung |
| Kalender, Kader, Anwesenheit, Zu-/Absage | Art. 6 Abs. 1 lit. b oder f | Datenminimierung; Gründe nur wenn erforderlich |
| Eltern-Kind-Verknüpfung | Art. 6 Abs. 1 lit. b/f | Sorge-/Vertretungsbefugnis verifizieren |
| Gesundheits- und Notfalldaten | Art. 6 plus Art. 9 Abs. 2, regelmäßig ausdrückliche Einwilligung nach lit. a | Freiwilligkeit, separate Zwecke, sofortige Sperre bei Widerruf; lebenswichtige Interessen nur im konkreten Notfall |
| Interne Spielerbewertung/Entwicklung | Art. 6 Abs. 1 lit. f oder b | Interessenabwägung, kinderfreundliche Transparenz, Trainerentscheidung, kurze Frist |
| Interne Profilfotos | regelmäßig Art. 6 Abs. 1 lit. a | Getrennt von Veröffentlichung; Widerruf technisch erzwingen |
| Öffentliche Fotos/Web/Social/Presse | Einwilligung; zusätzlich KUG-Prüfung | Je Kanal und Zweck getrennt; keine Kopplung |
| Push-Benachrichtigungen | je Zweck Einwilligung oder b/f | Geräteberechtigung, TDDDG-Prüfung, Inhaltsminimierung |
| Sicherheits-/Audit-Logs | Art. 6 Abs. 1 lit. f; Art. 32 | kurze Frist, Zugriffsbeschränkung, keine Inhaltsdaten ohne Bedarf |
| Support | Art. 6 Abs. 1 lit. b/f | Anhänge und Freitexte minimieren |
| BfV-Drittinhalt | Einwilligung/TDDDG § 25, sofern nicht technisch unbedingt erforderlich | vor Laden; Widerruf; Drittanbieterinformation |

Eine Einwilligung ist ungeeignet, wenn die Verarbeitung zwingend für die Mitgliedschaft erforderlich ist oder bei Verweigerung faktisch Nachteile entstehen. Dann muss eine andere tragfähige Rechtsgrundlage bestimmt und transparent erläutert werden.

## 11. Empfohlenes Lösch- und Aufbewahrungskonzept

Die folgenden Werte sind datenschutzfreundliche Arbeitsvorschläge, keine ungeprüften gesetzlichen Festfristen:

| Datenart | Vorschlag |
|---|---|
| Abgelehnte/abgebrochene Registrierungen | sechs Monate nach endgültiger Entscheidung, danach löschen/anonymisieren |
| Gesundheits-/Notfalldaten | nur während aktiver Betreuung; bei Widerruf sofort sperren, regelmäßig binnen 30 Tagen löschen, soweit kein dokumentierter Ausnahmegrund |
| Fotos nach Widerruf | sofort ausblenden, produktive Objekte binnen 30 Tagen und Backups nach dokumentiertem Zyklus entfernen |
| Absage-/Anwesenheitsgründe | Freitext spätestens 90 Tage nach Termin löschen; reine Statistik getrennt und minimiert |
| Fahrgemeinschaften und Treffpunktdaten | 90 Tage nach Termin löschen, sofern kein offener Vorgang |
| Push-Benachrichtigungen | regelmäßig 90 Tage; ungelesen höchstens nach dokumentiertem Bedarf |
| Push-Tokens | bei Ungültigkeit sofort deaktivieren; inaktive Geräte nach 90 Tagen löschen |
| Passwort-Reset | 15 Minuten gültig; technische Reste spätestens nach 24 Stunden löschen |
| Abgelaufene Sitzungen | 30–90 Tage nur für Sicherheitszwecke, danach löschen |
| Supporttickets | zwölf Monate nach Abschluss, sofern kein laufender Anspruch/Vorfall |
| Audit-/Sicherheitslogs | 90–180 Tage; längere Sperrfrist nur für konkreten Vorfall/Rechtsanspruch |
| Leistungsbewertungen/Entwicklungsnotizen | aktuelle plus höchstens folgende Saison beziehungsweise maximal 24 Monate; dann löschen/anonymisieren, wenn kein begründeter Bedarf |
| Ticker/Aufstellung/Sportergebnisse | sportliche Historie nur mit dokumentiertem Zweck; personenbezogene Details nach festgelegter Saisonfrist anonymisieren |
| Einwilligungsnachweise | solange die Verarbeitung läuft plus erforderliche Nachweis-/Verjährungsfrist; rohe Unterschriftszüge früher entfernen, wenn Hash/PDF als Nachweis genügt |
| Private Dokumente | zweckgebunden; bei Zweckfortfall/Widerruf löschen, Backups nach festem Zyklus auslaufen lassen |

Jede Frist benötigt Verantwortlichen, automatische Umsetzung, Kontrollbericht und dokumentierte Ausnahmebehandlung.

## 12. Verbindlicher Maßnahmenplan

### Vor Freigabe für weitere Eltern/Kinder (P0)

- [ ] DSFA abschließen und Datenschutzbeauftragtenpflicht entscheiden.
- [ ] Verzeichnis der Verarbeitungstätigkeiten und Rechtsgrundlagenmatrix verabschieden.
- [ ] Vollständige Art.-13-Information in die Registrierung integrieren; Kenntnisnahme von Einwilligung trennen.
- [ ] Legacy-Einwilligungsroute schließen; Foto-/Gesundheits-/Widerrufspolicies zentral erzwingen.
- [ ] Lösch- und Aufbewahrungskonzept samt automatisierten Jobs umsetzen.
- [ ] AV-Verträge, Regionen, Unterauftragsverarbeiter und Drittlandtransfers für Vercel, Neon und Google/Firebase prüfen und dokumentieren.
- [ ] Unsichere JWT-Defaults entfernen und Secret-Validierung erzwingen.
- [ ] Reset-Token aus Push und gespeicherten Benachrichtigungen entfernen.
- [ ] Hohe Dependency-Befunde aktualisieren oder nachweisbar mitigieren.

### Innerhalb von 30 Tagen (P1)

- [ ] Betroffenenexport vervollständigen und alle Rechteprozesse etablieren.
- [ ] Gesundheitsrollen nach Need-to-know reduzieren und regelmäßig rezertifizieren.
- [ ] Push-Inhalte minimieren und Vorschau datenschutzfreundlich voreinstellen.
- [ ] Datei-Scan, sichere Auslieferung und zuverlässige Objektlöschung ergänzen.
- [ ] Mobile Backups ausschließen und Offline-Daten weiter minimieren.
- [ ] `no-store`, CSP und weitere Security-Header produktiv setzen.
- [ ] Zentrales Rate-Limit, MFA für privilegierte Rollen und redigierte Logs einführen.
- [ ] Incident-Response-Prozess dokumentieren und testen.

### Innerhalb von 60–90 Tagen (P2)

- [ ] BfV-Widerruf und Drittanbieterübersicht vervollständigen.
- [ ] Öffentliche Kalenderlinks explizit widerrufbar machen.
- [ ] Kinder-/Elterninformationen in verständlicher Sprache bereitstellen.
- [ ] Schulungen, Vertraulichkeitsverpflichtungen und Rollenwechselprozess durchführen.
- [ ] Quartalsweise Berechtigungs-, Lösch-, Anbieter- und Dependency-Prüfung einplanen.
- [ ] Jährliche DSFA- und Datenschutzinformationen überprüfen; bei wesentlichen Änderungen sofort.

## 13. Empfohlene Freigaberegel

Die App sollte erst dann als datenschutzrechtlich produktionsreif für die breite Eltern-/Kindernutzung bezeichnet werden, wenn:

1. alle P0-Punkte technisch geschlossen oder rechtlich belastbar dokumentiert sind;
2. die DSFA kein unvertretbares Restrisiko ergibt;
3. sämtliche AV-/Transferunterlagen geprüft und unterschrieben sind;
4. ein vollständiger Löschtest einschließlich Blob-Dateien, Pushdaten und Backups erfolgreich protokolliert wurde;
5. Auskunft, Widerruf und Löschung mit Testkonten Ende-zu-Ende erfolgreich waren;
6. ein unabhängiger Sicherheits-/Penetrationstest keine hohen offenen Befunde zeigt;
7. Datenschutzbeauftragter oder spezialisierter Rechtsbeistand die finale Dokumentation geprüft hat.

Bis dahin ist höchstens ein eng begrenzter Testbetrieb mit Testdaten oder besonders restriktivem Pilotumfang vertretbar. Echte Gesundheitsdaten, Ausweisdokumente und veröffentlichte Kinderfotos sollten ohne geschlossene P0-Punkte nicht neu erhoben werden.

## 14. Maßgebliche offizielle Quellen

- [Datenschutz-Grundverordnung – EUR-Lex](https://eur-lex.europa.eu/legal-content/DE/TXT/?uri=CELEX:32016R0679)
- [BDSG § 38 – Datenschutzbeauftragte nichtöffentlicher Stellen](https://www.gesetze-im-internet.de/bdsg_2018/__38.html)
- [TDDDG § 25 – Schutz der Privatsphäre bei Endeinrichtungen](https://www.gesetze-im-internet.de/ttdsg/__25.html)
- [EDPB: Datenschutz-Folgenabschätzung](https://www.edpb.europa.eu/topics/accountability-and-compliance-tools/data-protection-impact-assessment_en)
- [EDPB: Kinder und Datenschutz](https://www.edpb.europa.eu/topics/key-gdpr-concepts/children_en)
- [EDPB: Datenschutzverletzungen](https://www.edpb.europa.eu/topics/security-data-breaches/personal-data-breaches_ga)
- [Datenschutzkonferenz: DSFA-Muss-Liste](https://www.datenschutzkonferenz-online.de/media/ah/20181017_ah_DSK_DSFA_Muss-Liste_Version_1.1_Deutsch.pdf)
- [Datenschutzkonferenz: Orientierungshilfe Telemedien/TDDDG](https://www.datenschutzkonferenz-online.de/media/oh/20221130_OH_Telemedien_Version_1.1.pdf)
- [BayLDA: Datenschutz im Verein – Musterinformation](https://www.lda.bayern.de/media/veroeffentlichungen/muster_1_verein.pdf)
- [Vercel Data Processing Addendum](https://assets.vercel.com/image/upload/q_auto/front/legal/dpa/Vercel_Inc_-_Data_Processing_Addendum.pdf)
- [Neon Data Processing Addendum](https://neon.com/pdf/DPA.pdf)
- [Neon Subprocessors](https://neon.com/subprocessors)
- [Firebase Privacy and Security](https://firebase.google.com/support/privacy/)
- [Google/Firebase Data Processing Terms](https://firebase.google.com/terms/data-processing-terms/)

## 15. Lokale technische Belegstellen

- `api/prisma/schema.prisma` – Datenkategorien und Beziehungen
- `api/src/controllers/privacy.controller.ts` – Export und Löschung
- `api/src/controllers/player-consents.controller.ts` – neuer Einwilligungsprozess
- `api/src/controllers/players.controller.ts` – Legacy-Einwilligungen und medizinische Profile
- `api/src/controllers/player-files.controller.ts` – Fotos und private Dateien
- `api/src/security/permissions.ts` – Rollen und sensible Rechte
- `api/src/lib/jwt.ts` – Token-Geheimnisse
- `api/src/controllers/auth.controller.ts` – Registrierung, Sessions und Passwort-Reset
- `api/src/services/notification.service.ts` – Push-Payloads und Zustellung
- `fc_teugn_app/lib/features/privacy/privacy_page.dart` – sichtbare Datenschutzinformation
- `fc_teugn_app/lib/core/offline_outbox.dart` – allgemeine Offline-Warteschlange
- `fc_teugn_app/lib/core/offline_ticker.dart` – Liveticker-Offline-Daten
- `fc_teugn_app/android/app/src/main/AndroidManifest.xml` – Android-Backup-/Gerätekonfiguration
- `web/bfv-widget.html` – BfV-Einwilligung und Drittinhalt

---

**Prüfurteil zum Ausgangsstand `662f248`:** Hoher Schutzbedarf, gute technische Grundlagen, aber mehrere wesentliche und teilweise kritische technische und organisatorische Datenschutzlücken.

**Technischer Nachprüfungsstand `1.5.73+92`:** Die im Quellcode unmittelbar schließbaren kritischen Sofortbefunde wurden umgesetzt und durch automatisierte Regressionen abgesichert. Der produktive Abhängigkeitsaudit enthält keine hohe oder kritische Meldung. Eine uneingeschränkte datenschutzrechtliche Freigabe ist damit noch nicht verbunden: Vor der breiten Nutzung müssen insbesondere DSFA, Verzeichnis der Verarbeitungstätigkeiten, Rechtsgrundlagen- und Fristenmatrix, AV-/Transferprüfung, Anbieter-Backuplöschung, Incident-Prozess sowie die unabhängige juristische und sicherheitstechnische Endprüfung dokumentiert abgeschlossen werden.
