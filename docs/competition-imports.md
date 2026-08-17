# BFV-/DFBnet-Spielplanimporte

Die App bietet eine providerunabhängige Importschicht für Spielpläne. Sie
verwendet ausschließlich vom Benutzer bereitgestellte CSV- oder ICS-Daten und
fragt keine inoffizielle oder nicht freigegebene SpielPLUS-Schnittstelle ab.

## Unterstützte Quellen

- `BFV_CSV`: CSV-Export beziehungsweise fachlich gleich aufgebauter Export
- `DFBNET_CSV`: DFBnet-CSV-Export
- `GENERIC_CSV`: eigene CSV-Vorlage
- `BFV_ICS`: direkt hochgeladene BfV-Spielplandatei mit `VEVENT` und `UID`
- `ICS`: sonstige standardisierte Kalenderdatei mit `VEVENT` und `UID`

Die Oberfläche bietet einen echten Datei-Upload für `.ics` und `.csv` (maximal
2 MB). Dateiformat und BfV-Quelle werden automatisch erkannt; das manuelle
Einfügen des Dateiinhalts bleibt nur als erweiterte Ausweichmöglichkeit erhalten.

Der BfV-Parser unterstützt die tatsächlich ausgelieferte Struktur, insbesondere:

- gefaltete iCalendar-Zeilen, die in der Folgezeile mit einem Leerzeichen
  fortgesetzt werden,
- Paarungen ohne Leerzeichen am Bindestrich, zum Beispiel
  `FC Teugn E7 1-SC Thaldorf E7`,
- die BfV-Notation aus Spielform und Mannschaftsnummer: `E7 1` wird als E1,
  `E7 2` als E2 und `E7 3` als E3 verarbeitet,
- Spielgemeinschaften mit dem Präfix `(SG)`,
- getrennte Übernahme von Sportstätte und postalischer Adresse sowie
- UTC-Termine mit korrekter Darstellung in der lokalen Zeitzone.

CSV kann Komma oder Semikolon als Trennzeichen verwenden. Deutsche und
englische Spaltennamen werden normalisiert. Empfohlen sind:

```csv
Spielkennung;Datum;Uhrzeit;Gegner;Heimspiel;Wettbewerb;Staffel;Spieltag;Ort;Adresse;Status;ToreFCTeugn;ToreGegner;BFVUrl
```

Fehlt eine externe Spielkennung, wird aus Termin, Gegner und Ort eine stabile
Ersatzkennung erzeugt. Eine echte externe Kennung ist dennoch vorzuziehen.

## Sicherer Ablauf

1. Trainer oder berechtigter Betreuer wählt Mannschaft, Format und Quelle.
2. Der Inhalt wird serverseitig validiert und normalisiert.
3. Eine persistierte Vorschau zeigt neue, geänderte, unveränderte,
   widersprüchliche und ungültige Zeilen.
4. Erst nach Bestätigung erfolgt der Import in einer Datenbanktransaktion.
5. Externe Referenzen und Prüfsummen verhindern doppelte Spielimporte.
6. Lokale Änderungen nach dem letzten Abgleich werden als Konflikt behandelt
   und standardmäßig nicht überschrieben.
7. Eine bewusste Option kann lokale Daten zugunsten der Quelle ersetzen,
   jedoch niemals ein Spiel einer fremden Mannschaft übernehmen.
8. Wiederholtes Anwenden desselben Importjobs ist idempotent.
9. Der Gegner wird innerhalb der Altersklasse über Verein und
   Mannschaftsbezeichnung mit dem vorhandenen Gegnerstamm verknüpft. Dadurch
   bleiben vorhandene Logos und Stammdaten erhalten. Fehlt ein eindeutiger
   Gegnerstammsatz, darf das Spiel trotzdem importiert werden und die Vorschau
   weist verständlich darauf hin.
10. Ein bereits manuell angelegtes Spiel mit gleichem Gegner und exakt gleicher
    Anstoßzeit wird aktualisiert und mit der ICS-UID verbunden, statt ein
    Duplikat zu erzeugen. Manuelle ICS-Uploads und der automatische BfV-Abgleich
    teilen dafür dieselbe externe Referenzlogik.

Importjobs, einzelne Zeilen und externe Referenzen bleiben für Nachvollziehbarkeit
erhalten. Das Anwenden wird zusätzlich im Audit-Log protokolliert.

## Tatsächlicher Integrationsstand

CSV- und ICS-Import, Vorschau, Konflikterkennung und Duplikatschutz sind
funktionsfähig. Eine direkte BFV-/SpielPLUS-API-Anbindung wird ausdrücklich
nicht behauptet. Dafür wären eine offiziell freigegebene Schnittstelle,
Nutzungsbedingungen und Zugangsdaten des Verbandes erforderlich.
