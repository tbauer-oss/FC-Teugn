# Mannschaftsmitteilungen und Benachrichtigungen

Das Kommunikationsmodul bündelt Mannschaftsmitteilungen, persönliche
In-App-Benachrichtigungen und Web Push in einer gemeinsamen Oberfläche.

## Funktionen

- Trainer und berechtigte Organisationsrollen können Mitteilungen für eine
  oder mehrere ihrer Mannschaften erstellen.
- Zielgruppen sind alle Mitglieder, Eltern, Spieler, Trainer/Organisation oder
  explizit ausgewählte Empfänger.
- Mitteilungen unterstützen Normal-, Wichtig- und Dringend-Priorität,
  Entwürfe, sofortige sowie zeitgesteuerte Veröffentlichung, Ablaufzeitpunkte,
  Lesebestätigungen und sichere HTTPS-Anhänge.
- Eltern und Spieler sehen ausschließlich veröffentlichte, nicht abgelaufene
  Mitteilungen ihrer Mannschaft und Zielgruppe.
- Jede Veröffentlichung erzeugt entsprechend der persönlichen Einstellungen
  In-App-Benachrichtigungen und optional Push-Auslieferungen.
- Benutzer können In-App und Push pro Kategorie getrennt konfigurieren.

## Web Push

Die Web-App registriert einen eigenen Service Worker (`web/push-sw.js`) und
übermittelt das Browser-Abonnement authentifiziert an das Backend. Abgelaufene
Browser-Endpunkte (HTTP 404/410) werden automatisch deaktiviert.

Für Produktion müssen im Backend-Vercel-Projekt folgende Umgebungsvariablen
gesetzt werden:

- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`
- `VAPID_SUBJECT` (zum Beispiel `mailto:admin@fc-teugn.de`)

Ein Schlüsselpaar kann einmalig mit
`npx web-push generate-vapid-keys` erzeugt werden. Private Schlüssel dürfen
nicht in Git eingecheckt werden.

Android-Push ist im Datenmodell vorbereitet, benötigt für die native
Auslieferung aber noch ein Firebase-Projekt und die zugehörigen
Produktions-Zugangsdaten. Die Oberfläche behauptet deshalb nicht, dass
Android-Push bereits aktiviert sei.

## Zeitgesteuerte Veröffentlichung

Fällige Mitteilungen werden atomar veröffentlicht, sobald ein Benutzer die
Kommunikationsübersicht abruft. Mehrfachauslieferungen werden durch ein
statusgebundenes Update verhindert. Für eine minutengenaue Veröffentlichung
ohne App-Aufruf kann später zusätzlich ein Vercel Cron auf denselben Prozessor
geschaltet werden.

## Datenschutz und Nachvollziehbarkeit

- Mannschaftszugriff und Zielgruppe werden serverseitig geprüft.
- Leselisten sind nur für berechtigte Mitarbeiter sichtbar.
- Erstellen, Ändern und Veröffentlichen werden im Audit-Log protokolliert.
- Benachrichtigungspräferenzen und Geräteabonnements sind benutzerbezogen.
