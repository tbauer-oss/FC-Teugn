# FC Teugn Talents – Umsetzungsplan ohne BFV-API

Stand: 8. September 2026; 1.7.1+186 ist veröffentlicht und öffentlich geprüft.

Grundlage: Vergleichsbericht `APP-VERGLEICH-BFV-2026-09-07.md` und die anschließende Nutzeranweisung, die übrigen Verbesserungen professionell umzusetzen und zunächst die vollständige Änderungsliste zu liefern.

Nach dem Statusabgleich vom 8. September wurden die fehlende Entwicklungsansicht und native iOS-Push-Unterstützung ergänzt. Die Spieltagsorganisation im Autopiloten ist nun kompakt aufklappbar. Abgehakte Punkte beschreiben den dokumentierten Implementierungs- und bisherigen Prüfstand, keine vollständige Geräte- oder Vereinsabnahme. Nach den anschließenden Nutzerentscheidungen entfällt Google Play vollständig; eine native Apple-Veröffentlichung ist vorerst optional. Mit „Keine Tests bitte“ wurden weitere Tests, Startzeitmessungen und die Durchführung des vorbereiteten Vereinspiloten aus dem Auftrag genommen. Sie gelten als entfallen, nicht als erfolgreich durchgeführt. Details: [Nacharbeit 1.7.1](TALENTS-1.7.1-ABNAHME.md) und [bisheriger Umsetzungsstand](UMSETZUNGSSTAND-TALENTS-2026-09-07.md).

## Rahmen

- Kein BFV-API-Zugang verfügbar. Direkte Übertragung in den offiziellen Spielbericht, automatischer Bezug der Spielberechtigungsliste und API-basierte Festivalmeldungen sind nicht Teil der Umsetzung.
- Der vorhandene BFV-iCal-Abgleich, CSV-/ICS-Import, die BFV-Ansichten und der SpielPLUS-Zugang bleiben Grundlage der Verbandsanbindung.
- Exporte werden als nutzbare Kopier-, Druck- oder Dateiansichten angeboten. Ein Import in SpielPLUS wird ohne nachgewiesen unterstütztes Format nicht zugesichert.
- Android wird als signierte APK über MagentaCloud verteilt und über den vorhandenen Vereins-Updater aktualisiert. Google Play ist auf ausdrücklichen Nutzerwunsch ausgeschlossen; weder Einreichung noch eine separate Play-Version sind beauftragt.
- Auf dem iPhone ist die installierbare Web-App einschließlich Web-Push der vorgesehene Weg. Native Apple-Veröffentlichung, Apple-Signierung und native APNs-Geräteabnahme sind vorerst optionale spätere Schritte. Sie sind keine Voraussetzung für den Abschluss des verbindlichen Umfangs.
- Keine weiteren Tests auf Nutzerwunsch. Das betrifft auch Android-/iPhone-Gerätetests, Startzeitmessungen und den Vereinspilot. Vorhandene Prüfprotokolle dokumentieren ausschließlich bereits durchgeführte Prüfungen.
- Ziel ist ein verlässlicher, schnell bedienbarer Vereinsalltag für Familien und Trainer. Neue Funktionen werden in die bestehenden Abläufe eingebunden.

## Phase 1 – Zuverlässigkeit und schnelle Bedienung

### 1. BFV-Kalenderabgleich und Spieländerungen überarbeiten

- [x] Kalenderabgleich und manuelle Importe auf denselben fachlichen Ablauf für Spieländerungen führen.
- [x] Änderungen an Anstoß, Datum, Spielort und Absagestatus erkennen und mit vorherigen Werten speichern.
- [x] Betroffene Familien und Trainer über relevante Änderungen informieren; unveränderte Wiederholungsimporte bleiben ohne weitere Meldung.
- [x] Erinnerungen bei Verlegungen neu planen und bei Absagen entfernen beziehungsweise deaktivieren.
- [x] Lokale Änderungen und Quelldaten pro Feld vergleichen; einen lokalen Treffpunkt bei einer offiziellen Anstoßänderung erhalten.
- [x] Echte Konflikte als konkrete Feldänderungen mit verständlichen Auswahlmöglichkeiten darstellen.
- [x] Bei wesentlichen Änderungen eine nachvollziehbare erneute Rückmeldung unterstützen; bisherige Antworten erhalten, bis die neue Antwort vorliegt.
- [x] Letzten erfolgreichen Abgleich, Fehler, offene Konflikte und einen erneuten Versuch verständlich anzeigen.
- [x] Fällige Mannschaften fair abarbeiten; Laufzeitbegrenzung und unterschiedliche Abgleichintervalle berücksichtigen.
- [x] Fehlende Einträge in einer Kalenderquelle nicht ohne eindeutigen Absagenachweis als abgesagte Spiele behandeln.

Abnahme: Ein importierter Termin wird verlegt, während sein Treffpunkt lokal geändert wurde. Offizielle und lokale Informationen bleiben richtig; wiederholter Import erzeugt keine Duplikate, Kalender und Erinnerungen stimmen.

### 2. Push-Nachrichten und Erinnerungen konsistent machen

- [x] Änderungen, Rückmeldefristen, Dienste und Mitfahrthinweise gezielt an die zuständigen Personen richten.
- [x] Doppelte Hinweise aus mehreren Zuordnungen und wiederholten Jobs verhindern.
- [x] Bereits beantwortete, erledigte oder durch Abwesenheit geklärte Vorgänge aus passenden Erinnerungen herausnehmen.
- [x] Öffnen einer Nachricht direkt zum betroffenen Termin, Kind oder Vorgang führen; abgelaufene Ziele verständlich behandeln.
- [x] Vorhandene Kategorien, Geräteeinstellungen und Wiederholungsversuche konsistent verwenden.
- [x] „Gespeichert“, „Versand ausstehend“, „an Push-Dienst übergeben“ und „gelesen“ fachlich unterscheiden; keine unbestätigte Geräte-Zustellung behaupten.

Abnahme: Ein erledigter Vorgang erzeugt keine weitere Aufforderung; ein vorübergehender Versandfehler lässt sich ohne doppelte Benachrichtigung nachbearbeiten.

### 3. App-Start und Rückkehr in die App beschleunigen

- [x] Android-Intro nur beim ersten Start automatisch anbieten und den gesehenen Zustand lokal speichern.
- [x] Intro jederzeit überspringbar machen und zunächst stumm abspielen; freiwillige Wiedergabe unter „Über die App“ anbieten.
- [x] Start aus einer Push-Nachricht ohne Intro direkt zum Ziel führen.
- [x] Bereits geladene Inhalte bei Rückkehr sinnvoll weiterverwenden; unnötige Ladeaufrufe vermeiden.
- [x] Lade-, Fehler- und Wiederholungszustände der betroffenen Startabläufe vereinheitlichen.

Entfallen auf Nutzerwunsch: weitere Startzeitmessungen auf definierten Testgeräten. Der frühere Warmstart-Zielwert von ungefähr zwei Sekunden wurde auf echten Geräten nicht nachgewiesen.

### 4. Bezeichnungen und Navigation korrigieren

- [x] „Mitgliedschaft beantragen“ beim App-Zugang durch eine eindeutige Formulierung ersetzen.
- [x] Navigation, Hilfe und Seitenüberschriften bei Nachrichten, Rückmeldungen und Aufgaben aufeinander abstimmen.
- [x] Zähler aus tatsächlich zum Ziel gehörenden Datensätzen berechnen; insbesondere „Offene Aufgaben“ im Eltern-Dashboard korrigieren.
- [x] Für die bearbeiteten Ansichten direkte Wege und konsistente Zurück-Navigation herstellen.
- [x] Fehlermeldungen mit einer konkreten nächsten Handlung versehen; neue Eingaben nicht unnötig verlieren.

## Phase 2 – Familien und Mannschaftsorganisation

### 5. Allgemeine Abwesenheiten neu ergänzen

- [x] Einmalige Zeiträume und wiederkehrende Abwesenheiten pro Spieler erfassen.
- [x] Geltung für Mannschaften sowie Training, Spiele oder alle passenden Termine auswählbar machen.
- [x] Vorhandene und später angelegte Termine berücksichtigen.
- [x] Überschneidungen mit Regeltrainings-Zusagen und Einzelrückmeldungen nach klaren Vorrangregeln behandeln.
- [x] Einzelne Ausnahmen, vorzeitiges Beenden und Änderungen unterstützen, ohne frühere Antworten zu verlieren.
- [x] Verfügbarkeit in Rückmeldungen, Kaderplanung, Erinnerungen und Assistenzhinweisen verwenden.
- [x] Einen optionalen Grund nur den passenden berechtigten Personen anzeigen.

Abnahme: Ein Urlaubseintrag gilt auch für ein nachträglich angelegtes Spiel. Eine bewusst erfasste Ausnahme bleibt möglich und nachvollziehbar.

### 6. Familien-Assistent weiterentwickeln

- [x] Aufgaben nach Frist, Dringlichkeit und betroffenem Kind bündeln.
- [x] Rückmeldungen, Einwilligungen, Mitfahrten und übernommene Dienste korrekt zusammenführen.
- [x] Jede Aufforderung unmittelbar zur passenden Handlung führen.
- [x] Erledigte Vorgänge nach erfolgreichem Speichern aus der offenen Liste entfernen.
- [x] Terminänderungen verständlich mit bisheriger und neuer Information anzeigen.
- [x] Zeitüberschneidungen zwischen Terminen mehrerer Kinder kenntlich machen.
- [x] Einen klaren Zustand „Alles erledigt“ anbieten.

### 7. Spieltags-Assistent und Autopilot verbinden

- [x] Sportliche Vorbereitung und organisatorische Aufgaben in einer gemeinsamen Bereitschaftsansicht zusammenführen.
- [x] Fehlende Rückmeldungen, ungeklärte Mitfahrten und unbesetzte Dienste als konkrete Aufgaben anzeigen.
- [x] Bestehende Fahrgemeinschafts-, Trikotdienst- und Checklistenfunktionen direkt aus dieser Ansicht erreichbar machen.
- [x] Wiederverwendbare Checklisten für Heimspiel, Auswärtsspiel und Turnier auf der vorhandenen Grundlage anbieten.
- [x] Die vorhandene Spielzeitberechnung mit verständlichen Begründungen versehen.
- [x] Geplante und tatsächliche Einsatzzeiten für die nächste Trainerentscheidung vergleichbar machen.
- [x] Trainerkorrekturen und bestehende Veröffentlichungsregeln erhalten.

### 8. Echte Umfragen ergänzen

- [x] Umfrage mit Frage, Antwortmöglichkeiten, Zielmannschaften und Endzeit anlegen.
- [x] Einfach- und Mehrfachauswahl unterstützen.
- [x] Abstimmungseinheit ausdrücklich festlegen: Person, Familie oder Kind; Mehrfachvertretungen berücksichtigen.
- [x] Antworten bis zum Ablauf änderbar machen.
- [x] Ergebnisansicht, Teilnahmezahl und festgelegte Sichtbarkeit anbieten.
- [x] Gezielte Erinnerung für noch ausstehende Antworten unterstützen.
- [x] Umfragen abschließen, archivieren und vom normalen Nachrichtenverlauf aus öffnen.

### 9. Einladung und Registrierung vereinfachen

- [x] Zeitlich begrenzte, widerrufbare Einladungslinks und QR-Codes mit vorausgewählter Mannschaft und Rolle anbieten.
- [x] Bestehende Konten zur zusätzlichen Mannschaft führen, statt ein zweites Konto anzulegen.
- [x] Kinderzuordnungen über den vorhandenen Prüfprozess absichern.
- [x] Freigabestatus und nächste Schritte verständlich darstellen.
- [x] Installations-, Einladungs- und Anmeldeweg zusammenführen, damit der Einladungskontext erhalten bleibt.
- [x] Passende Hilfe direkt im jeweiligen Schritt anbieten.

## Phase 3 – Entwicklung und ergänzende Vereinsfunktionen

### 10. Individuelle Entwicklungsziele ergänzen

- [x] Ein bis drei aktive Lernziele pro Kind mit Zeitraum und verantwortlichem Trainer verwalten.
- [x] Ziele mit Übungen der vorhandenen Bibliothek und passenden Trainingsplänen verknüpfen.
- [x] Kurze Beobachtungen, Fortschritt und Zielabschluss festhalten.
- [x] Zielverlauf mit den vorhandenen Entwicklungsnotizen und Statistiken verbinden. „Verlauf & Statistik“ zeigt pro Kind und Ziel die eigenen Zielbeobachtungen, vorhandene sichtbare Notizen und erfasste Leistungen im Zielzeitraum. Export als gemeinsamer Entwicklungsrückblick; private Notizen, Mannschaftszuordnung und Freigaben werden serverseitig geprüft.
- [x] Bestehende Sichtbarkeitsrechte für Trainer, Eltern und Spieler verwenden.
- [x] Einen kompakten Entwicklungsrückblick für Gespräche anbieten.

### 11. Mannschaftskasse – entfällt

Auf ausdrücklichen Wunsch des Nutzers am 7. September 2026 vollständig aus dem Umfang entfernt. Keine Kasse, Belege, Zahlungsübersichten oder Saldoübernahmen.

### 12. Turnierabläufe und manuelle SpielPLUS-Arbeit erleichtern

- [x] Bestehende Turnier- und Festivaltermine mit klaren Treffpunkten, Kadern, Diensten und Veranstalterlinks verbinden.
- [x] Lesbare, kopierbare und druckbare Kader- und Spieltagsübersichten anbieten.
- [x] Relevante externe BFV-/SpielPLUS-Seiten vom passenden Kontext aus erreichbar machen.
- [x] Offizielle Daten, manuell gepflegte Daten und Angaben aus dem Kalenderimport verständlich unterscheiden.

Es wird keine zweite vereinsübergreifende Festivalplattform aufgebaut. Direkte Meldungen im BFV-System bleiben ein externer Vorgang.

### 13. Saisonwechsel für die erweiterten Funktionen vervollständigen

- [x] Den vorhandenen geführten Wechsel mit konkreten Jugend- und Jahrgangsbeispielen prüfen.
- [x] Elternverknüpfungen, Spielerhistorie, Mitgliedschaften und Rollen beim Wechsel kontrollieren.
- [x] Für offene Entwicklungsziele, Abwesenheiten passende Übernahmeentscheidungen vorsehen.
- [x] Abgeschlossene Termine, Umfragen und Dienste im Archiv halten.
- [x] Vorschau und Warnhinweise bei unklaren Zuordnungen konkret formulieren.
- [x] Wiederholte Ausführung gegen doppelte Übernahmen absichern.

## Phase 4 – Auslieferung und Abnahme

### 14. Installation und Updates vereinfachen

- [x] Eine gemeinsame Einstiegsseite für Android und iPhone innerhalb des vorhandenen Webauftritts anbieten.
- [x] Den passenden Installationsweg erkennen und in wenigen verständlichen Schritten erklären.
- [x] Vorhandene Android-Updates mit verständlichem Status, Versionshinweisen und Wiederholungsmöglichkeit prüfen.
- [x] iPhone-PWA-Anleitung und Push-Aktivierung in den passenden Nutzungskontext bringen.
- [x] Signierte Android-APK und Store-Datei (AAB) erstellen, iOS-Projekt vorbereiten und die native Kompilierung auf macOS nachweisen. Android-Vereinsdownload und Web-App veröffentlichen.
- [x] Native iOS-Push-Implementierung ergänzen: Berechtigungsentscheidung, APNs-Tokenbereitschaft, FCM-Registrierung als IOS, Tokenwechsel, Vordergrundanzeige, Navigation und Backend-Versand einschließlich Geräteverwaltung.
- [x] Hilfe und Schulungsunterlagen an die tatsächlich ausgelieferten Abläufe anpassen.

Google-Play-Einreichung entfällt auf Nutzerwunsch. Das bereits erstellte AAB ist ein Build-Artefakt und keine angekündigte Store-Veröffentlichung.

Optional für später: Native Apple-App mit Apple-Signierung und realer Firebase-/APNs-Konfiguration auf einem iPhone prüfen und gegebenenfalls bei TestFlight/App Store einreichen. Dieser Ausbau wird getrennt vom vorgesehenen iPhone-Web-App-Weg geführt; er ist nicht als erledigt markiert.

### 15. Offline-Verhalten und Qualität der betroffenen Abläufe absichern

- [x] Bestehende Offline-Warteschlangen auf die neuen Abläufe abstimmen; je Aktion bewusst entscheiden, ob sie offline speicherbar ist oder eine Online-Verbindung benötigt.
- [x] Lokal gespeicherte und serverseitig bestätigte Änderungen eindeutig unterscheiden.
- [x] Wiederholung nach Verbindungsabbruch ohne doppelte Vorgänge ermöglichen; echte Konflikte sichtbar lösen.
- [x] Betroffene mobile Ansichten mit kleinen Displays, großen Schriftgrößen und zugänglichen Bedienelementen prüfen.
- [x] Änderungen an Datenmodell und Migrationen mit bestehenden Daten in einer isolierten Testumgebung verifizieren.
- [x] Fachliche Tests für Verlegungen, Abwesenheiten, Abstimmungsrechte, Saisonwechsel ergänzen.
- [x] Durchgängige Abläufe für Trainer und Familien prüfen; bestehende passende Prüfungen ausführen.
- [x] Pilot mit zwei Trainern und fünf Eltern anhand gleicher Aufgaben vorbereiten.
- [x] Versionshinweise und nachvollziehbare Abnahmeergebnisse je Umsetzungspaket dokumentieren.

Entfallen auf Nutzerwunsch: zusätzliche Abnahmen mit privaten Android-/iPhone-Geräten und die Durchführung des Vereinspiloten. Interne Flutter-, Backend-, Integrations-, Emulator- und Build-Prüfungen bleiben gemäß der anschließenden Klarstellung ausdrücklich Teil der Umsetzung. Der Pilot war ein freiwilliger Probelauf mit zwei Trainern und fünf Eltern anhand typischer App-Aufgaben. Er wurde nicht durchgeführt; es liegen keine entsprechenden Messwerte vor. Die vorbereitete Anleitung bleibt als Dokumentation erhalten.

## Abschließender Umfang

Auslieferung über Android-APK/MagentaCloud und iPhone-Web-App. Keine Mannschaftskasse, keine Google-Play-Veröffentlichung. Interne Tests und technische Prüfungen werden weiter durchgeführt. Native Apple-Veröffentlichung bleibt optional. Nicht durchgeführte Prüfungen werden nicht nachträglich als bestanden ausgewiesen.
