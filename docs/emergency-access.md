# Geschützte Notfallansicht

Die Notfallansicht stellt Trainerinnen, Trainern und anderen ausdrücklich
berechtigten Teamrollen für einen konkreten Termin die tatsächlich anwesenden
Spieler sowie notwendige Kontakt- und Gesundheitsinformationen bereit.

## Sicherheitsmodell

- Der reguläre Access-Token und die Berechtigung `VIEW_SENSITIVE_PLAYER`
  werden weiterhin geprüft.
- Vor dem Öffnen muss die angemeldete Person ihr Passwort erneut bestätigen.
- Das Backend stellt danach einen eigenen, auf Benutzer und Termin begrenzten
  Notfall-Token mit fünf Minuten Laufzeit aus.
- Der Token bleibt nur im Speicher des geöffneten Dialogs und wird weder in
  Local Storage noch im Secure Storage gespeichert.
- Passwort-Fehlversuche werden begrenzt.
- Freigaben, fehlgeschlagene Passwortbestätigungen und jedes Öffnen werden im
  Audit-Log protokolliert.
- Die Ansicht bietet bewusst keinen Export und keine Teilen-Funktion.

## Datenumfang

Die Liste verwendet die tatsächliche Anwesenheit, sobald sie für den Termin
erfasst wurde. Andernfalls dienen bestätigte Zusagen als vorläufige Grundlage.
Angezeigt werden ausschließlich:

- Name und optionales Profilbild des Spielers,
- verknüpfte Erziehungsberechtigte mit Telefonnummer und Abholberechtigung,
- priorisierte Notfallkontakte,
- Allergien, Medikamente, Erkrankungen und ausdrücklich hinterlegte
  Notfallhinweise.

Normale Kalenderantworten enthalten diese sensiblen Daten nicht.

## Konfiguration

In Produktion sollte `EMERGENCY_ACCESS_SECRET` als eigenständiges langes,
zufälliges Secret gesetzt werden. Ist es nicht gesetzt, leitet das Backend aus
dem regulären Access-Token-Secret eine separate Signaturklasse ab.

## API

- `POST /events/:id/emergency-access` mit `{ "password": "…" }`
- `GET /events/:id/emergency-view` mit Header
  `X-Emergency-Access-Token: <kurzlebiger Token>`
