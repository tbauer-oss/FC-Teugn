# Sichere Sitzungen und Token-Widerruf

Die App verwendet kurzlebige Access-Tokens und rotierende Refresh-Tokens.
Refresh-Tokens werden auf dem Endgerät verschlüsselt gespeichert und in der
Datenbank ausschließlich als SHA-256-Hash geführt.

## Ablauf

1. Anmeldung oder Registrierung erstellt eine neue Sitzungsfamilie.
2. Das Access-Token ist 15 Minuten gültig.
3. Bei einem HTTP-401 erneuert die App die Sitzung automatisch.
4. Jedes Refresh-Token ist nur einmal verwendbar und wird bei der Erneuerung
   ersetzt.
5. Eine erneute Verwendung eines alten Tokens widerruft die gesamte
   Sitzungsfamilie.
6. Abmelden widerruft die aktuelle Sitzung; `POST /auth/logout-all` widerruft
   alle Sitzungen eines angemeldeten Kontos.

Der aktuelle Freigabe-, Rollen- und Mannschaftsstatus wird bei geschützten
Anfragen erneut aus PostgreSQL gelesen. Sperrungen und Rollenänderungen wirken
dadurch auch auf bereits ausgestellte Access-Tokens.

## Umgebungsvariablen

- `ACCESS_TOKEN_SECRET`: eigener langer Zufallswert für Access-Tokens
- `REFRESH_TOKEN_SECRET`: davon verschiedener langer Zufallswert für
  Refresh-Tokens
- `PUBLIC_APP_URL`: öffentliche Web-App-Basis für sichere Aktionslinks
- `RESEND_API_KEY`: ausschließlich serverseitig gespeicherter Resend-Schlüssel
  mit `Sending access` für `fc-teugn-talents.de`
- `RESEND_ACCOUNT_FROM_EMAIL`: Absender für Kontomails,
  `FC Teugn Talents <account@fc-teugn-talents.de>`
- `RESEND_SUPPORT_FROM_EMAIL`: Absender für Support- und Aktivierungsmails,
  `FC Teugn Talents Support <support@fc-teugn-talents.de>`
- `RESEND_ACCOUNT_REPLY_TO` und `RESEND_SUPPORT_REPLY_TO`: optionale betreute
  Antwortadressen; `RESEND_REPLY_TO` kann als gemeinsamer Fallback dienen

`JWT_SECRET` wird nur als Kompatibilitätsalias für bestehende Installationen
akzeptiert. In Produktion müssen beide aktiven Secrets explizit gesetzt sein.

## Passwort zurücksetzen

`POST /auth/password-reset/request` antwortet unabhängig davon, ob ein Konto
existiert. Für freigegebene Konten wird ein zufälliger, nur als SHA-256-Hash
gespeicherter Einmaltoken erzeugt. Resend versendet den 15 Minuten gültigen
Link an die im Konto hinterlegte Adresse. Der API-Schlüssel bleibt dabei
ausschließlich im Backend. Der Passwort-Reset versendet bewusst keine
Pushnachricht. Wird die E-Mail von Resend nicht angenommen, wird der erzeugte
Token verworfen und kann durch eine neue Anfrage ersetzt werden.

Nach erfolgreicher Änderung werden alle Refresh-Tokens und biometrischen
Zugänge des Kontos widerrufen. Der Einmallink kann kein zweites Mal verwendet
werden.

## Client-Speicherung

Flutter verwendet `flutter_secure_storage`. Auf Android kommen Keystore-basierte
Verfahren, auf Apple-Plattformen der Keychain und im Web ausschließlich sichere
HTTPS-/Localhost-Kontexte zum Einsatz. Das Access-Token bleibt nur im
Arbeitsspeicher.
