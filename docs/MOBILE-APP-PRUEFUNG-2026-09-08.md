# Appweite mobile Prüfung · FC Teugn Talents

Stand: 8. September 2026. Basis: 1.7.2+187, Arbeitszweig `codex/app-mobile-audit`.

Der Prüfdurchlauf umfasst die Routen und gemeinsamen Oberflächen der gesamten Flutter-App. Die gefundenen Layoutfehler sind im Projekt korrigiert. Die anschließende Veröffentlichung erfolgt auf ausdrücklichen Nutzerwunsch als **1.7.3+188** für Web und den signierten Android-Vereinsdownload. Veröffentlichungsnachweise stehen in `TALENTS-1.7.3-ABNAHME.md`.

## Umfang und Nachweise

- Statische Inventur von **48 unterschiedlichen Routenmustern** und **82 Dateien mit Oberflächenkomponenten**. Die Rollenrouten verwenden teilweise dieselben Seiten. Die Dateizahl ist keine Zahl einzeln visuell abgenommener Fenster.
- Vollständige bestehende Flutter-Suite plus **84 neue mobile Szenarien: insgesamt 715 Tests erfolgreich**.
- Neue Szenarien: 320 × 740 bei 100 % und 200 % Schrift, 390 × 844 bei 100 %, 740 × 360 im Querformat bei 130 %. Dialoge zusätzlich mit simuliertem Tastaturbereich bis 300 Pixel. Lange Personen-, Mannschafts- und Betrefftexte sowie gefüllte Ansichten gehören zu den Testdaten.
- Bestehende Prüfungen erfassen außerdem größere Ansichten, Faltgeräte, Hell/Dunkel, Navigation, Rollenrechte, Rückmeldungen, Mitfahrten, Kalender, Kader und Trainingsplanung.
- Gerenderte Bildkontrolle der überarbeiteten Teamaufgaben, Materialansichten, Datenschutzansichten, Supportdialoge, Hilfe und Familiennavigation. Zusätzlich dunkle Ansicht und große Schrift mit Tastatur. Ausschließlich synthetische Daten; keine Nachrichten und keine Änderungen an echten Mitgliederdaten.
- Flutter Analyze ohne Befunde; Web-Release-Build erfolgreich. Nach der abschließenden Umstellung der Support-Statusauswahl auf einen vom gespeicherten Ticket gesteuerten Wert wurden deren vier mobilen Szenarien sowie anschließend alle 84 mobilen Szenarien mit gefüllten Checklisten erneut erfolgreich geprüft.

## Korrekturen

1. **Dialoge in der gesamten App:** 91 bisher nicht ausdrücklich scrollbare Standarddialoge lassen Überschrift und Inhalt bei knapper Höhe gemeinsam scrollen. Das betrifft unter anderem Termine, Spielerprofile, Mitgliederverwaltung, Spieltag, Trainingsplanung und Sicherheitsbestätigungen. Aktionen bleiben außerhalb dieses Scrollbereichs erreichbar.
2. **Auswahllisten:** 55 weitere Auswahlfelder nutzen die verfügbare Breite; 115 Menüs erhalten flexible Zeilenhöhen. Lange Namen und vergrößerte Schrift werden nicht mehr durch starre Auswahlbreiten beziehungsweise Zeilenhöhen verdrängt.
3. **Teamorganisation:** kompakter Kopf, horizontal erreichbare Register, platzsparende Karten und Statusanzeige unter dem Titel auf Smartphones. Auch im kurzen Querformat bleibt Raum für den Inhalt. Aufgaben-, Material- und Vorlagenkategorien werden verständlich benannt.
4. **Familie & Team:** eine kompakte, horizontal scrollbare Registerleiste ersetzt mehrere Zeilen Auswahlchips. Das aktive Register ist beim Öffnen sichtbar; der Wechsel zwischen den tatsächlichen Routen ist getestet. Karten und Leerzustände benötigen weniger Abstand.
5. **Datenschutz:** kurze mobile Einleitung, kleinere Aktionskarten und flexible Hinweisbeschriftungen. Datenkopie, Löschung und weitere Anträge sind früher erreichbar. Antragsformulare, insbesondere die Auswahl langer Betroffenenrechte, funktionieren mit großer Schrift und Tastatur.
6. **Support:** kompakter Einleitungsbereich; kürzeres Beschreibungsfeld auf Smartphones. Der Ticketdialog verwendet einen gemeinsamen scrollbaren Inhalt anstelle einer festen Gesamthöhe mit konkurrierender Nachrichtenliste und Antwortformular. Die Statusauswahl passt sich der Breite an und zeigt den tatsächlich gespeicherten Status.
7. **Hilfe:** kompakter Kopf, einklappbare Erläuterungen zur Hilfe, kompakte Direktaktionen und umbrechende Ergebnisüberschrift. Bei großer Schrift wird die Aktionsübersicht einspaltig.
8. **Funktionssuche und Spielerwechsel:** verschachtelte, intrinsisch nicht messbare Listen in Standarddialogen wurden durch gemeinsam scrollbare Inhalte ersetzt.

## Bereichsmatrix

„Widget“ bedeutet eine ausgeführte Prüfung mit Flutter-Oberfläche und definierten Testdaten. „Quelle/Vertrag“ kennzeichnet technische Prüfungen ohne vollständige visuelle Abnahme jedes Zustands. Bestehende und neue Tests wurden gemeinsam ausgeführt.

| Bereich | Einbezogene Ansichten / Fenster | Prüfung |
|---|---|---|
| Start und Navigation | App-Shell, mobile Hauptnavigation, Mehr-Menü, Funktionssuche, Rollenwechsel, Zurücknavigation | Widget, Navigation und Barrierefreiheit; `navigation_structure_test`, `navigation_bar_accessibility_test`, `widget_test` |
| Anmeldung und Konto | Login, Registrierung, Passwort-Rücksetzung, Freigabehinweis, Kontoeinstellungen | Widget/Vertrag; `auth_mobile_accessibility_test`, `account_settings_mobile_test`, Sitzungs- und Registrierungsprüfungen |
| Trainer- und Familienstart | Dashboard, nächste Termine, Hinweise, Familienaufgaben, Benachrichtigungen | Widget; Dashboard-, Familienassistent- und Ladefehlerprüfungen |
| Team und Spieler | Teamübersicht, Spielerliste, Profil, Mannschaftszuordnung, Kontakte, Dokumente, Gesundheit, Einwilligungen und Unterschrift | Widget/Vertrag; `trainer_team_responsive_test`, `trainer_players_page_test`, `mobile_player_profile_test`, `digital_signature_capture_test`; gemeinsame Dialogprüfung |
| Kalender | Monat, Tagesauswahl, Terminansicht/-bearbeitung, Teilnahme und Serienaktionen | Widget/Vertrag; `event_editor_responsive_test`, `calendar_month_swipe_test`, Termin- und Rückmeldungsprüfungen |
| Spiele und Historie | Trainer-/Elternliste, Spielplanung, Wettbewerb, vergangene Partien | Widget/Vertrag; `trainer_matches_mobile_test`, `mobile_parent_matches_test`, Wettbewerbs- und Historienprüfungen |
| Spieltag | Übersicht, Kader, Aufstellung, Spielerwechsel, Autopilot, Ticker, Bewertung, Familienansicht | Widget/Vertrag; `matchday_overview_responsive_test`, `match_squad_responsive_test`, `matchday_autopilot_mobile_test`, Turnier- und Tickerprüfungen |
| Mitfahrten und Trikotdienst | Angebot, Bedarf, direkte Buchung für Eltern/Kinder, Stornierung, Spieltagsstatus | Widget/Modell; `carpool_booking_mobile_test`, `kit_laundry_duty_card_test`, bestehende Mitfahrzusammenfassungen |
| Training und Belegung | Übersicht, Planer, Übungen, Bausteine, Trainingszeiten, Hallen- und Platzbelegung | Widget/Modell; `training_planner_mobile_test`, `training_occupancy_mobile_test`, `training_page_resilience_test` |
| Statistik und Entwicklung | Leistung, Teilnahme, Spielhistorie, Lernzielentwicklung | Widget/Modell; `statistics_performance_mobile_test`, `goal_development_view_test`, Statistikprüfungen |
| Nachrichten und Push | Mitteilungen, Verfassen, Direktkontakt, Benachrichtigungen, Einstellungen, Geräteverwaltung | Widget/Vertrag; `communications_access_test`, `admin_push_device_management_mobile_test`, Push- und Geräteprüfungen |
| Familie & Team | Aufgaben, Abwesenheiten, Umfragen, Lernziele, Einladungen, Berichte | Neue gefüllte Widgets und Formulare; tatsächlicher Register-/Routenwechsel; `talents_workflows_test`, Entwicklungs- und Familienassistentprüfungen |
| Aufgaben und Material | Aufgaben, Material, Ausgabe, Rückgabe, Checklisten und Vorlagen | Neue Widgetprüfungen aller drei Register sowie vier Erstellungs-/Ausgabedialoge; bestehende Modellprüfungen |
| Vereinsverwaltung | Mannschaften, Saison, Regelprofile, Zuordnungen, Standardaufstellung | Widget/Quelle; `organization_mobile_compact_test`, `team_default_lineup_dialog_test`, Organisationsmodelle und gemeinsame Dialogprüfung |
| Mitglieder und Rechte | Freigaben, Mitgliederverwaltung, Rollenrechte, Adminperspektive | Widget/Vertrag; `member_permissions_dialog_responsive_test`, Mitgliederfilter-, Rollen- und Navigationsprüfungen; Adminperspektive zusätzlich Quellprüfung |
| Datenschutz | Informationen, Datenexport, Betroffenenrechte, Löschantrag, Verwaltungsdialoge | Neue Widgetprüfungen der Nutzerseite und drei Dialoge; `privacy_information_center_test`; Verwaltungsaktionen Quelle/Vertrag |
| Support | Eingang, neue Anfrage, Ticketverlauf, Antwort, interne Notiz, Status | Neue gefüllte Widgetprüfungen für Nutzer und Systemadministration einschließlich Tastatur |
| Hilfe und Installation | Eltern-/Trainerhilfe, Artikelsuche, Installationsanleitung, Info-/Update-/Pushhinweise | Neue Widgetprüfungen plus `help_page_test`, `app_about_sheet_test`, `initial_push_prompt_test`, PWA-/Android-Konfigurationsprüfungen |
| Externe Integrationen | BFV-/SpielPlus-Browser, Turnierplan und Import | App-eigene Einbettung, Importdialog und Integration/Vertrag geprüft. Die Gestaltung externer Webseiten liegt außerhalb der Flutter-App und dieser Bildkontrolle. |

## Grenzen der Aussage

In den ausgeführten Szenarien sind keine bekannten Layoutüberläufe übrig. Eine appweite technische Prüfung ersetzt keine Sichtabnahme jeder denkbaren Kombination aus Gerät, Schrift, Daten, Filter und Betriebssystemdialog. Insbesondere Verwaltungsaktionen mit echten Konten, externe Webseiten und private physische Telefone wurden nicht durchgeklickt. Dafür wurden keine produktiven Daten verändert.

Die Systemschrift bleibt vergrößerbar. Mannschaftskasse und Google-Play-Veröffentlichung bleiben ausgeschlossen; native Apple-Veröffentlichung bleibt optional. Die vorhandene Mitfahrfunktion für Eltern selbst und ihre Kinder bleibt erhalten.

## Dateien und Reproduktion

- Neue Tests: `fc_teugn_app/test/whole_app_mobile_audit_test.dart` und synthetische Organisationsdaten unter `test/support/mobile_audit_fixtures.dart`.
- Gesamttests: `flutter test --no-pub`; gezielt: `flutter test --no-pub test/whole_app_mobile_audit_test.dart`.
- Analyse: `flutter analyze --no-pub`; Build: `flutter build web --release --no-pub`.
- Lokale Nachweise: `artifacts/mobile-audit-2026-09-08/` enthält Protokolle, Routen-/UI-Inventur und elf gerenderte PNGs. `preview-source.dart` dokumentiert den Generator; er wurde nur temporär unter `fc_teugn_app/tmp/` ausgeführt.

## Routeninventur

- `/bfv-browser`
- `/install`
- `/join`
- `/login`
- `/parent`
- `/parent/account`
- `/parent/bfv`
- `/parent/events`
- `/parent/family`
- `/parent/help`
- `/parent/matches`
- `/parent/matches/:matchId`
- `/parent/matches/history`
- `/parent/messages`
- `/parent/operations`
- `/parent/players`
- `/parent/players/:playerId`
- `/parent/privacy`
- `/parent/statistics`
- `/parent/support`
- `/parent/talents/:section`
- `/pending`
- `/register`
- `/reset-password`
- `/spielplus-browser`
- `/trainer`
- `/trainer/account`
- `/trainer/approvals`
- `/trainer/bfv`
- `/trainer/events`
- `/trainer/family`
- `/trainer/help`
- `/trainer/matches`
- `/trainer/matches/:matchId`
- `/trainer/matches/history`
- `/trainer/messages`
- `/trainer/operations`
- `/trainer/organization`
- `/trainer/players`
- `/trainer/players/:playerId`
- `/trainer/privacy`
- `/trainer/statistics`
- `/trainer/support`
- `/trainer/talents/:section`
- `/trainer/team`
- `/trainer/training`
- `/trainer/training/:trainingId`
- `/trainer/view-as`
