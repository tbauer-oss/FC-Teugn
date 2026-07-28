# Spieltag, Kader, Aufstellung und Liveticker

Der Spielbereich erweitert bestehende `Event`-Termine vom Typ `MATCH`. Dadurch
bleiben Kalender, Rückmeldungen und Fahrgemeinschaften erhalten, während
Spieltage zusätzliche fachliche Daten bekommen.

## Funktionsumfang

- Spielarten und Status von geplant bis beendet
- Wettbewerb, Staffel, Spieltag, Platz, Schiedsrichter und BFV-Referenzen
- konfigurierbare Spielabschnitte und Spielzeiten
- Kadernominierung mit `NOMINATED`, `ON_CALL` und `DECLINED`
- getrennte Veröffentlichung von Kader und Aufstellung
- grafischer, verschiebbarer Aufstellungseditor für 3 bis 11 Spieler
- interne taktische Notizen werden Eltern und Spielern nicht ausgeliefert
- mobile Liveticker-Steuerung mit serverbasierter Uhr
- Tore, Spielstart, Halbzeit, Fortsetzung, Unterbrechung und Abpfiff
- idempotente Ereignisse über `clientEventId`
- Sequenznummern für Polling und Wiederverbindung
- Korrekturbuchung statt physischer Löschung veröffentlichter Ereignisse
- Audit-Einträge für Kader, Aufstellungen und Tickeraktionen

## API

```text
GET    /matches
GET    /matches/:id
PUT    /matches/:id
PUT    /matches/:id/squad
POST   /matches/:id/squad/publish
PUT    /matches/:id/lineup
GET    /matches/:id/ticker?after=<sequence>
POST   /matches/:id/ticker/events
POST   /matches/:id/ticker/undo
```

Ticker-Schreibzugriffe benötigen `MANAGE_LIVE_TICKER`, Aufstellungen
`MANAGE_LINEUPS`. Alle Lese- und Schreibzugriffe werden zusätzlich auf die
zugeordneten Mannschaften begrenzt.

## Echtzeit und schlechte Verbindung

Die produktive Ausbaustufe verwendet ein kurzes, sequenzbasiertes Polling.
Das passt zu serverlosen Vercel-Funktionen und verhindert dauerhaft offene
WebSocket-Verbindungen. Jeder Client sendet eine eindeutige `clientEventId`;
wiederholte Übertragungen erzeugen deshalb kein doppeltes Tor. Der Flutter-Client
speichert den zuletzt geladenen Spielstand benutzer- und terminbezogen für
maximal sieben Tage.

Tickeraktionen werden vor dem Netzaufruf in einer persistenten, pro Benutzer
getrennten Warteschlange gespeichert. Bei einem Verbindungsabbruch zeigt die
App den optimistisch fortgeschriebenen Spielstand und alle ausstehenden
Aktionen deutlich an. Die Übertragung wird in Originalreihenfolge automatisch
wiederholt. Nach einer möglicherweise verlorenen Serverantwort bleibt dieselbe
`clientEventId` erhalten, sodass der Server keine doppelten Ereignisse erzeugt.
Einträge verfallen nach 48 Stunden; maximal 100 Aktionen werden vorgemerkt.

Korrekturen werden bewusst nicht offline vorgemerkt, weil eine spätere
„Letzte Aktion“-Auflösung bei zwischenzeitlichen Aktionen eines zweiten
Trainers mehrdeutig wäre. Die Oberfläche erklärt in diesem Fall, dass zunächst
ein synchroner Spielstand benötigt wird.
