# Messenger 2.0 – verbindliches 30-Tage-Löschkonzept

Direktnachrichten und zugehörige Medien besitzen bereits beim Anlegen ein
konkretes `expiresAt`. Der Bereinigungsjob läuft alle fünf Minuten und entfernt
nach Ablauf zuerst das private Speicherobjekt und danach Nachrichten- sowie
Dateimetadaten aus PostgreSQL. Schlägt das Entfernen des Speicherobjekts
vorübergehend fehl, bleiben die Metadaten für einen sicheren Wiederholungsversuch
erhalten; der Zugriff aus der App ist ab `expiresAt` trotzdem gesperrt.

Für produktive Datenbank- und Objektspeicher-Sicherungen gilt ebenfalls eine
maximale Aufbewahrung von 30 Tagen. `MESSENGER_BACKUP_RETENTION_DAYS` dokumentiert
die beim Provider eingestellte Frist und darf höchstens 30 sein; andernfalls
startet die API nicht. Bei jedem Providerwechsel ist diese Einstellung vor dem
Umschalten zu prüfen. Manuelle Exporte mit Messenger-Inhalten sind unzulässig
oder müssen in denselben automatischen Löschlauf aufgenommen werden.

Die App zeigt für jede Nachricht und jeden Anhang das konkrete Löschdatum sowie
einen dauerhaft sichtbaren Hinweis auf die 30-Tage-Frist. Gerätesicherungen der
Android-App sind im Manifest deaktiviert.
