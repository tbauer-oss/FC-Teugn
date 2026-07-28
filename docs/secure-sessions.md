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

`JWT_SECRET` wird nur als Kompatibilitätsalias für bestehende Installationen
akzeptiert. In Produktion müssen beide aktiven Secrets explizit gesetzt sein.

## Client-Speicherung

Flutter verwendet `flutter_secure_storage`. Auf Android kommen Keystore-basierte
Verfahren, auf Apple-Plattformen der Keychain und im Web ausschließlich sichere
HTTPS-/Localhost-Kontexte zum Einsatz. Das Access-Token bleibt nur im
Arbeitsspeicher.
