# Geschützte Spielerfotos und Dokumente

Spielerfotos und Unterlagen werden nicht öffentlich im Web-Build abgelegt.
Das Backend speichert sie als private Objekte in Vercel Blob. Die App erhält
nur kurzlebige, signierte Lese-URLs (standardmäßig zehn Minuten).

## Produktion

- Im Vercel-Projekt `fc-teugn-backend` muss ein privater Blob Store verbunden
  sein. Vercel stellt dadurch `BLOB_READ_WRITE_TOKEN` bereit.
- Die Datenbankmigration
  `20260729043000_private_player_files` wird beim Backend-Deployment durch
  `prisma migrate deploy` ausgeführt.
- Ein Upload ist auf 4 MB sowie PDF, JPEG, PNG oder WebP begrenzt. Damit bleibt
  er unter dem Request-Limit der Vercel Functions.
- Spielerfotos werden in der App mittig quadratisch zugeschnitten, auf maximal
  1024 × 1024 Pixel verkleinert und als JPEG komprimiert.

## Berechtigungen und Datenschutz

- Fotos ändern: Trainerteam mit `MANAGE_PLAYERS` oder verknüpfte
  Sorgeberechtigte.
- Dokumente lesen: Rollen mit `VIEW_SENSITIVE_PLAYER`, das eigene Spielerkonto
  oder verknüpfte Sorgeberechtigte.
- Dokumente verwalten: Rollen mit `MANAGE_DOCUMENTS` oder verknüpfte
  Sorgeberechtigte.
- Storage-Pfade und dauerhafte Blob-URLs werden nicht an Clients ausgegeben.
- Upload, Austausch und Entfernen werden im Audit-Log protokolliert.
- Beim Ersetzen oder Entfernen wird das Objekt im Storage gelöscht und der
  Datensatz logisch als gelöscht markiert.

## Betrieb und Wiederherstellung

Die PostgreSQL-Sicherung enthält Metadaten, Versionen und Audit-Einträge, aber
nicht den Dateiinhalt. Der Blob Store ist deshalb separat in die
Datensicherungs- und Aufbewahrungsrichtlinie des Vereins aufzunehmen. Nach einer
Wiederherstellung müssen Datenbank und Blob-Bestand denselben Sicherungszeitpunkt
abbilden.
