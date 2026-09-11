# Doppelspiel-Sonderfreigabe und höhenangepasste Aufstellung

## Bedienung

1. Für einen Spieler zunächst das erste Spiel zusagen.
2. Im zweiten Spiel unter **Kader** auf den Rückmeldungsstatus des Spielers tippen.
3. **Doppelspiel freigeben** auswählen, das bereits zugesagte Spiel auswählen und **Für beide zusagen** bestätigen.

Bei Turnieren wird dies im **Turnierkader** erledigt, nicht in einzelnen Turnierpartien. Beide Spiele/Turniere müssen am selben Kalendertag in Europe/Berlin liegen und vom handelnden Trainer verwaltet werden dürfen. Bereits gespeicherte Freigaben sind im Auswahldialog gekennzeichnet. Ohne zweite Zusage wird keine Freigabe angeboten.

Bei einer bereits gespeicherten Einladungsliste kann das zuständige Trainerteam auch weitere berechtigte Spieler aus dem angezeigten Jugendkader bestätigen. Die fehlende Einladung wird zusammen mit der Rückmeldung gespeichert. Das gilt auch für eigene Kinder des Trainers. Reine Elternantworten bzw. der persönliche Familienmodus dürfen keine zusätzlichen Spieler aufnehmen; ausdrücklich entfernte Spieler bleiben ausgeschlossen.

## Wirkung und Grenzen

- Freigabe gilt exakt für ein Spieler-/Spielpaar und den bestätigten Tag, nicht pauschal für die Jugend oder den ganzen Kalender.
- Die bestehende zweite Zusage, ihr Kaderplatz und die Aufstellung werden durch die neue Zusage nicht automatisch entfernt.
- Erneute Zusagen durch Eltern, Trainer und die gemeinsame Konfliktroutine beachten die Freigabe.
- Ausdrückliche Absagen bleiben möglich. Eine neue Zusage zu einem nicht freigegebenen dritten Termin unterliegt weiterhin der üblichen Tagesautomatik.
- Eltern/Spieler können keine Ausnahme erteilen. Der Server prüft Trainerzuständigkeit für beide Termine, unabhängig von der UI.
- Die Freigabe ist kein Nominierungsersatz: Die bewusste Kaderauswahl bleibt beim Trainer.
- Bei Verschiebung auf einen anderen Tag ist eine neue Freigabe nötig. Löschen eines Spiels oder Spielers entfernt zugehörige Freigaben automatisch.
- Die Freigabe wird online und transaktional zusammen mit der Zusage gespeichert; ein Spieler-/Tag-Lock serialisiert konkurrierende Zusagen. Erneute Übermittlung verwendet denselben kanonischen Paar-Schlüssel.
- Die Freigabe wird mit Urheber und Zeitpunkt gespeichert und im Auditlog protokolliert.

## Datenbank und Auslieferung

Migration: `20260911120000_same_day_match_approval`. Sie muss vor Auslieferung des neuen Backends angewendet werden. Keine bestehende Rückmeldung wird durch die Migration geändert. Bestehendes Prisma-/Neon-Setup bleibt unverändert.

## Aufstellung

Bei breiten, höhenbegrenzten Ansichten folgt das Feld der tatsächlich verbleibenden Tab-Höhe. Die Bedienleiste scrollt unabhängig; die Aufstellung bleibt stehen. Bei wenig Höhe stehen Positionskürzel neben dem Trikot, ohne die Namensschrift zu verkleinern. Einzelne Namenshöhen werden gemessen, damit ein langer Name nicht sämtliche Spielerfelder vergrößert. Normierte Aufstellungskoordinaten ändern sich beim Größenwechsel nicht.

Sehr kleine Fenster, stark vergrößerte Schrift oder außergewöhnlich dicht platzierte Spieler erhalten weiterhin einen begrenzten verschiebbaren Feldbereich mit sichtbarem Hinweis, statt abgeschnittener Namen. Die Smartphone-Ansicht, Vollbild und physische Foldable-Trennung bleiben erhalten.

## Prüfung

- `api/tests/same-day-match-integration.cjs` wird über `npm run test:talents:integration` mit allen Migrationen auf isoliertem PGlite ausgeführt (keine produktiven Daten).
- Prüft Standardkonflikte, Trainer-/Elternrechte, identische/andere Tage, Kindpartien, fehlende zweite Zusage, Erhalt von Kader und Aufstellung, wiederholte/rückwärts erteilte Freigabe, Elternantworten, andere Spieler, ältere automatisierte Antworten, ausdrückliche Absagen, dritten Termin, Verschiebung und Löschkaskade.
- Flutter-Tests prüfen den Sonderfreigabe-Dialog bei 320 px und vergrößerter Schrift sowie die Desktop-Höhe mit 7/11 Spielern und den echten Turnier-Kopfbereichen. Bestehende Telefon-/Foldable-/Vollbild-Tests bleiben aktiv.
