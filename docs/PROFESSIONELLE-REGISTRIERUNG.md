# Professionelle Registrierung und Freigabe

## Registrierungsablauf

Die öffentliche Registrierung erfasst:

- Vor- und Nachname,
- E-Mail-Adresse und ein Passwort mit mindestens zehn Zeichen,
- optionale Telefonnummer,
- gewünschte Rolle,
- eine oder mehrere Mannschaften,
- bei Eltern den Namen des Kindes und die Beziehung,
- verpflichtende Datenschutz- und Nutzungsbestätigung,
- optionale Push-Einwilligung.

Jede Zustimmung verweist auf die konkrete `ConsentTextVersion`. Damit bleibt
auch nach einer späteren Textänderung nachvollziehbar, welche Fassung bestätigt
wurde. Neue Accounts erhalten grundsätzlich `PENDING`; nur der erste Benutzer
eines noch leeren Vereins wird als initialer `CLUB_ADMIN` freigegeben.

Login und Registrierung sind pro IP und Route zeitlich begrenzt. Der Server
akzeptiert JSON-Nutzlasten bis maximal 1 MB.

## Freigabezentrum

Unter **Mitglieder & Freigaben** sieht die berechtigte Vereinsseite:

- die beantragte Rolle und alle gewünschten Mannschaften,
- Kontaktangaben,
- Kind und Beziehung bei Eltern,
- Push-Einwilligung,
- interne Prüfnotizen,
- die vollständige Änderungshistorie.

Mögliche Entscheidungen:

- Rolle, Mannschaften und Kind-Zuordnung prüfen und freigeben,
- eine Rückfrage mit interner Notiz markieren,
- Registrierung mit Begründung ablehnen,
- bestehende Accounts blockieren oder archivieren.

Die Statuswerte sind `PENDING`, `APPROVED`, `REJECTED`, `BLOCKED` und
`ARCHIVED`. Der Bearbeitungsstand wird getrennt als `NEW`, `IN_REVIEW`,
`NEEDS_INFO` oder `COMPLETED` geführt.

Freigaben, Ablehnungen, Rückfragen, Rollen, Teamzuordnungen und Kind-Verknüpfung
werden in `RegistrationHistory` und im allgemeinen `AuditLog` protokolliert.

## Datenschutz

- Einwilligungen werden nicht als unversionierte Boolean-Felder behandelt.
- Pflichttexte müssen aktiv und aktuell sein, sonst wird die Registrierung
  abgelehnt und die Oberfläche muss neu laden.
- Push bleibt freiwillig.
- Eltern-Kind-Verknüpfungen entstehen erst nach administrativer Prüfung.
- Abgelehnte, blockierte oder archivierte Accounts können sich nicht anmelden.
- Passwörter werden weiterhin ausschließlich gehasht gespeichert.
