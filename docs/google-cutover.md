# Google-Umstellung und Übergang für installierte Apps

Zielstand: 1.8.1+195. Firebase Hosting unter `app.fc-teugn-talents.de`, Express
auf Cloud Run in `europe-west3`, private Dateien und Scheduler-Status im privaten
Google-Bucket. Neon/PostgreSQL, Resend und der bestehende MagentaCLOUD-Download
bleiben erhalten. Das ist die Ablösung von Vercel als Anwendungslaufzeit;
eine vollständige Migration dieser weiteren Anbieter ist damit nicht behauptet.

## Veröffentlichung

1. CI prüft Backend, Migrationen, HTTP-Flows, Flutter, Android-Push und Builds.
2. `release_google.yml` akzeptiert nur einen erfolgreichen CI-Lauf desselben
   Repositorys und des aktuellen main/master-Commits.
3. Cloud Run, dann Firebase Hosting, dann die bereits signierte APK und zuletzt
   das Update-Manifest werden veröffentlicht. Ein manueller CI-Lauf allein
   veröffentlicht nichts; die Freigabe erfolgt mit seiner `validation_run_id`.
4. Der alte Android-Manifestpfad bleibt erreichbar. `update_policy.json` setzt
   Build 195 als Mindestversion. Das Manifest verweist auf die versionierte APK,
   damit ein späterer Upload nicht die Datei eines früheren Manifests ersetzt.

Die Cloud-Run-Antwort wartet auf registrierte Hintergrundaufgaben und beide
Scheduler-Invalidierungen. Google-Speicher übernimmt den gemeinsamen Status;
Generationsbedingungen verhindern gleichzeitige Scheduler-Leases. Fehlende
Cache-Einträge führen zum normalen Scan. Ein Fehler beim Lease-Zugriff lässt den
Scheduler-Aufruf fehlschlagen, damit er wiederholt werden kann. Cloud Run und
Cloud Scheduler haben 300 Sekunden Zeitlimit, die Lease 360 Sekunden.

Gelöschte FileAsset-Metadaten behalten einen dauerhaften Retry-Marker, bis das
private Objekt entfernt ist. Der Scheduler bearbeitet bis zu 100 ausstehende
Löschungen pro Stunde. Bestehende Löschpfade warten ebenfalls auf den Speicher.

## Übergangsadressen

`deploy_backend_vercel.yml` und `deploy_flutter_web_vercel.yml` veröffentlichen
jetzt ausschließlich `legacy-bridge/`, standardmäßig als Preview. Erst
`production: true` ersetzt die vorhandene Produktionsbereitstellung.
Die API nutzt einen Proxy-Rewrite, damit POST-Inhalt und Anmeldung erhalten
bleiben. Sie enthält weder eigene API-Funktionen noch Cronjobs. Die Web-Brücke
führt zur neuen Domain und entfernt alte PWA-Caches beim Worker-Update.

Die alten Vercel-Projekte dürfen während dieses Übergangs nicht gelöscht werden:
ihre `*.vercel.app`-Adressen sind nicht zu Google übertragbar.
Der Betreiber hat die neue BfV-Domain am 09.09.2026 als freigegeben bestätigt.

Vor und nach dem Umschalten der alten API den Blob-Migrationsworkflow ausführen.
Vorhandene Objekte werden jetzt mittels SHA-256 verglichen, fehlende bei
`execute: true` kopiert. Abweichende vorhandene Objekte werden als Fehler
gemeldet und nicht überschrieben. Keine Quelldatei wird automatisch gelöscht.
Das Entwicklungswerkzeug `@vercel/blob` wird beim Container-Build entfernt.

## Grenzen bereits installierter Versionen

Builds 193/194 verstehen `mandatory: true`, benötigen zum Start einer gespeicherten
Anmeldung aber weiterhin die alte API. Ihr Dialog kann nach dem Aufruf des
Android-Installers geschlossen sein, auch wenn die Installation abgebrochen wird.
Diese Lücke lässt sich in einer bereits installierten Binärdatei nicht
nachträglich reparieren. Build 195 prüft vor der Anmeldung und gibt die App erst
nach erfolgreicher Versionsprüfung frei; ein Installer-Aufruf allein reicht
nicht. Bei fehlender Verbindung beim ersten Start wird ein erneuter Versuch
angeboten. Web und iOS behalten ihren bisherigen Startweg.

## Pro-Tarif

Der Tarif wurde geprüft, aber nicht geändert. Das Team „Tobi’s projects“ umfasst
auch DFS- und smartPMS-Projekte. Der Nutzer entschied am 09.09.2026 ausdrücklich:
erst FC Teugn umstellen, danach über den Tarif entscheiden. Der aktuelle
Abrechnungszeitraum endet laut Dashboard am 14.09.2026. Hobby ist nach den
[Vercel-Bedingungen](https://vercel.com/docs/plans/hobby) auf persönliche,
nicht kommerzielle Nutzung beschränkt. Ein kleiner Proxy allein belegt keine
Tarifberechtigung des gesamten Teams.

## Optionale Demo

Die Demo-Pipeline verwendet jetzt ein separates Google-Projekt und eigene
`DEMO_GCP_PROJECT_ID`, `DEMO_GCP_WORKLOAD_IDENTITY_PROVIDER`,
`DEMO_GCP_SERVICE_ACCOUNT`, `DEMO_GCS_BUCKET`, `DEMO_APP_URL` und
`DEMO_API_BASE_URL`. Diese Ressourcen müssen vorher bereitstehen, einschließlich
Cloud-Run-Laufzeitkonto, Artifact Registry, Firebase Hosting und getrennten
Secret-Manager-Werten. Die Pipeline lehnt das Produktionsprojekt als Demo ab.
Push und E-Mail bleiben dort gesperrt; die private Google-Dateispeicherung ist
davon unabhängig. Eine vorhandene Demo wird nicht automatisch verändert.
