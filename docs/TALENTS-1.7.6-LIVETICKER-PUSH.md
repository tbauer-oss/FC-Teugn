# FC Teugn Talents 1.7.6+191 – hörbare Liveticker-Ereignisse

## Fehler und Korrektur

Beim Spiel gegen Langquaid wurden Spielstände angezeigt, aber aktive Ereignismeldungen mit Ton fehlten. Im Android-Code war der Kanal `fc_teugn_live_match` ausdrücklich ohne Ton und Vibration eingerichtet. FCM-Liveticker-Nachrichten aktualisierten ausschließlich diese laufende Anzeige; auch im Vordergrund wurde keine zusätzliche Meldung erzeugt. Diese Konfiguration bestand bereits vor der Neon-Verbrauchsoptimierung.

Ein eigener Kanal `fc_teugn_live_events` zeigt jetzt Anpfiff, Heim- und Auswärtstore sowie Abpfiff mit hoher Wichtigkeit, normalem Benachrichtigungston und Vibration. Die laufende Spielstandsanzeige bleibt stumm. Nur ein empfangenes FCM-Ereignis erzeugt die aktive Meldung; normale Abfragen beim geöffneten Spieltag tun das nicht.

Die Ereignisart wird im namenfreien Backend-Payload mitgegeben. Die Android-Anzeige verwendet Mannschaften, Spielstand und Minute, keine Spielernamen oder freien Kommentartexte. Ein Tipp öffnet das betreffende Spiel. Eine begrenzte lokale Ereignishistorie verhindert wiederholte Alarme durch doppelte Push-Zustellungen, auch nach dem Wegwischen einer Meldung.

Die Empfängerauswahl und das persönliche Liveticker-Push-Opt-in bleiben bestehen. Androids Lautlosmodus, Nicht-stören-Modus, Benachrichtigungsberechtigung und vom Nutzer gewählte Kanaleinstellungen werden respektiert. Der Live-Takt, die Ruhephasen der App und die Neon-Optimierung werden nicht geändert.

## Produktionsdiagnose

Nur lesende, aggregierte Abfragen in der bestehenden Neon-Datenbank bestätigten für das Spiel TSV Langquaid E1 gegen FC Teugn am 8. September 2026 insgesamt 126 Android- und 21 Web-Zustellungen mit Status `SENT`; keine Zustellung dieses Spiels stand auf `FAILED` oder `PENDING`. Das bedeutet Annahme durch den Pushanbieter, keine Bestätigung einer Anzeige auf dem jeweiligen Handy.

Zwischen Anlegen der Benachrichtigung und Anbieterannahme lagen bei Android durchschnittlich 0,55 Sekunden, maximal 1,14 Sekunden; bei Web durchschnittlich 0,51 Sekunden, maximal 0,80 Sekunden. Damit zeigt diese Messung keine Verzögerung des Erstversands durch die neuen Hintergrund-Ruhephasen. Für weitere In-App-Benachrichtigungen bestand kein Pushauftrag; persönliche Einstellungen und verfügbare Geräte werden nicht ungefragt geändert.

## Prüfung

304 Backend-Tests und drei Vorprüfungen bestanden lokal; außerdem neun gezielte Flutter-Prüfungen für Android-Push, Version und Updateverteilung. Sechs neue native Android-Tests prüfen den tatsächlichen Receiver und die gebauten Benachrichtigungen mit Robolectric: hörbarer Ereigniskanal, ruhige Spielstandsanzeige, eigene Meldung pro Ereignis, Duplikate nach Wegwischen, Deep Link, Datenschutz, Legacy-Payload und Android-Berechtigung.

Der lokale Gradle-Teststart scheiterte vor dem Build an `Unable to establish loopback connection`, auch mit IPv4. Die nativen Tests sind deshalb als verpflichtender Schritt in der bestehenden Linux-CI vor dem signierten APK-Build aufgenommen. Dort wurden sie erfolgreich kompiliert und ausgeführt (`:app:testDebugUnitTest`, `BUILD SUCCESSFUL`). Der vollständige CI-Lauf bestand außerdem mit 722 Flutter-Tests, 304 Backend-Tests, drei Backend-Vorprüfungen, Formatprüfung, Flutter-Analyse, isolierter PostgreSQL-Integration und HTTP-Ende-zu-Ende-Prüfungen. Es wurden keine Testnachrichten an produktive Familien gesendet. Ein realer Ton auf dem konkreten Nutzergerät wurde nicht ferngeprüft.

## Veröffentlichung

Am 8. September 2026 erfolgreich veröffentlicht, Quellstand `ddcaf4e8e32a0ba1ad775e65f2b889e4c4361144`:

- [Backend](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34262268968) und [Web](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34262268933) erfolgreich.
- [Gesamte CI, signierte APK und Magenta](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34262268964) erfolgreich; Magenta-Upload um 20:33 Uhr MESZ abgeschlossen.
- Beide Web-Domains liefern 1.7.6, Build 191. Das öffentliche Magenta-Manifest entspricht exakt dem CI-Artefakt.
- Öffentliche APK vollständig heruntergeladen und geprüft: Paket `de.fcteugn.jugend`, Version **1.7.6+191**, Größe **92.564.866 Byte**, SHA-256 `8272669ad3d6702f9f78c4cd9e4f13038fa4766383638bf8312461e9857872ac`.
- APK-Signatur gültig und unverändert zum vorherigen Build: Zertifikat-SHA-256 `14e38172691d04bcf26210c217c8210301ecd35b3aaa3a18bba2b555f30847bd`. Im veröffentlichten DEX sind der neue Ereigniskanal und die lokale Duplikaterkennung enthalten.
- [Android-Update über Magenta](https://magentacloud.de/s/xkgHEESdKbQ6XMP). Die Android-Korrektur erfordert die Installation dieses Updates. Keine Veröffentlichung bei Google Play oder Apple.

Lokale Nachweise: `artifacts/release-1.7.6-build-191/`, insbesondere `production-push-evidence.json`, `ci-release.log`, `public-release-verification.json` und `apk-signature.log`.

Grundlagen: [Android-Benachrichtigungskanäle](https://developer.android.com/reference/android/app/NotificationChannel), [FCM-Nachrichtentypen](https://firebase.google.com/docs/cloud-messaging/customize-messages/set-message-type), [Robolectric](https://robolectric.org/getting-started/).
