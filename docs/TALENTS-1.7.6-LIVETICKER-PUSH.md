# FC Teugn Talents 1.7.6+191 – hörbare Liveticker-Ereignisse

## Fehler und Korrektur

Beim Spiel gegen Langquaid wurden Spielstände angezeigt, aber aktive Ereignismeldungen mit Ton fehlten. Im Android-Code war der Kanal `fc_teugn_live_match` ausdrücklich ohne Ton und Vibration eingerichtet. FCM-Liveticker-Nachrichten aktualisierten ausschließlich diese laufende Anzeige; auch im Vordergrund wurde keine zusätzliche Meldung erzeugt. Diese Konfiguration bestand bereits vor der Neon-Verbrauchsoptimierung.

Ein eigener Kanal `fc_teugn_live_events` zeigt jetzt Anpfiff, Heim- und Auswärtstore sowie Abpfiff mit hoher Wichtigkeit, normalem Benachrichtigungston und Vibration. Die laufende Spielstandsanzeige bleibt stumm. Nur ein empfangenes FCM-Ereignis erzeugt die aktive Meldung; normale Abfragen beim geöffneten Spieltag tun das nicht.

Die Ereignisart wird im namenfreien Backend-Payload mitgegeben. Die Android-Anzeige verwendet Mannschaften, Spielstand und Minute, keine Spielernamen oder freien Kommentartexte. Ein Tipp öffnet das betreffende Spiel. Eine begrenzte lokale Ereignishistorie verhindert wiederholte Alarme durch doppelte Push-Zustellungen, auch nach dem Wegwischen einer Meldung.

Die Empfängerauswahl und das persönliche Liveticker-Push-Opt-in bleiben bestehen. Androids Lautlosmodus, Nicht-stören-Modus, Benachrichtigungsberechtigung und vom Nutzer gewählte Kanaleinstellungen werden respektiert. Der Live-Takt, die Ruhephasen der App und die Neon-Optimierung werden nicht geändert.

## Prüfung

304 Backend-Tests und drei Vorprüfungen bestanden lokal; außerdem neun gezielte Flutter-Prüfungen für Android-Push, Version und Updateverteilung. Sechs neue native Android-Tests prüfen den tatsächlichen Receiver und die gebauten Benachrichtigungen mit Robolectric: hörbarer Ereigniskanal, ruhige Spielstandsanzeige, eigene Meldung pro Ereignis, Duplikate nach Wegwischen, Deep Link, Datenschutz, Legacy-Payload und Android-Berechtigung.

Der lokale Gradle-Teststart scheiterte vor dem Build an `Unable to establish loopback connection`, auch mit IPv4. Die nativen Tests sind deshalb als verpflichtender Schritt in der bestehenden Linux-CI vor dem signierten APK-Build aufgenommen. Veröffentlichungsnachweise werden nach erfolgreichem Abschluss ergänzt. Es werden keine Testnachrichten an produktive Familien gesendet.

Grundlagen: [Android-Benachrichtigungskanäle](https://developer.android.com/reference/android/app/NotificationChannel), [FCM-Nachrichtentypen](https://firebase.google.com/docs/cloud-messaging/customize-messages/set-message-type), [Robolectric](https://robolectric.org/getting-started/).
