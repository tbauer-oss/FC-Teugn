# Professionelle Mannschaftsprofile

Der Bereich „Verein & Mannschaften“ verwaltet vollständige
Mannschaftsstammdaten. Neben Name, Kurzname und Spielklasse gehören dazu:

- Mannschaftstyp, Ausrichtung und Jahrgänge
- Beschreibung, Trainingsort, reguläre Trainingszeiten und Heimspielstätte
- BFV- und DFBnet-Referenzen
- aktive und inaktive Mannschaften
- automatisch aus freigegebenen Mannschaftsmitgliedschaften ermittelte
  Trainer, Co-Trainer, Teammanager und Jugendleitung
- ein geschütztes Mannschaftsfoto

## Datenschutz und Berechtigungen

Mannschaftsfotos werden im privaten Vercel-Blob-Speicher abgelegt. Die API gibt
keine dauerhafte öffentliche Blob-Adresse aus, sondern erzeugt für angemeldete
berechtigte Benutzer eine kurzlebige signierte URL. Das öffentliche
Organisationsverzeichnis enthält weder Fotos noch E-Mail-Adressen der
Verantwortlichen.

Vereinsadministration und Jugendleitung können alle Mannschaften ihres Vereins
pflegen. Trainer können nur Mannschaften bearbeiten, für die sie eine
freigegebene Mitgliedschaft mit der Berechtigung `MANAGE_TEAM` besitzen. Jede
Änderung und jeder Fotoaustausch wird im Auditprotokoll festgehalten.

## API

- `GET /organization/context` liefert die sichtbaren vollständigen Profile.
- `POST /organization/teams` legt ein Team im aktuellen Verein an.
- `PATCH /organization/teams/:id` aktualisiert ein berechtigtes Team.
- `POST /organization/teams/:id/photo` speichert ein privates Bild bis 4 MB.
- `DELETE /organization/teams/:id/photo` entfernt das aktuelle Bild.

Die Migration `20260729233000_professional_team_profiles` ergänzt die neuen
Felder und die geschützte Foto-Relation. Sie muss vor dem Start der aktualisierten
API mit `prisma migrate deploy` angewendet werden.
