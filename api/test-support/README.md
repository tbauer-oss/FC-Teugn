# Isolierte Talents-Abnahme

Dieser Ordner enthält ausschließlich die zusätzliche Testlaufzeit. Sie ist keine Produktionsabhängigkeit.

Aus dem Projektverzeichnis:

```powershell
npm.cmd ci --prefix api/test-support --cache tmp/npm-cache
npm.cmd run test:talents:integration --prefix api
```

Der Test startet eine flüchtige PGlite-Datenbank auf `127.0.0.1:55439`, setzt seine Datenbankadresse selbst und verwendet ausschließlich synthetische Daten. Er liest keine produktive Datenbankkonfiguration. Alle alten SQL-Migrationen werden ausgeführt; anschließend werden Altdaten erzeugt und die Talents-Migration auf diesen Bestand angewendet.

`node api/tests/talents-integration.cjs --serve` lässt anschließend eine lokale API auf Port 4000 für Browserprüfungen laufen. Die Konten `admin@example.invalid`, `coach@example.invalid` und `parent@example.invalid` haben nur in dieser flüchtigen Umgebung das Passwort `Teugn-Test-2030!`. Die Testumgebung niemals extern bereitstellen. Nach Beenden des Prozesses werden die Daten verworfen.

Die Prisma-Verbindung ist auf einen Poolplatz begrenzt. Diese Abnahme prüft Transaktionen, Migrationen und Rechte, aber ersetzt keinen PostgreSQL-Lasttest.
