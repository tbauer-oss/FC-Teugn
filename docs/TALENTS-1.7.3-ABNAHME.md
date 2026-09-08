# FC Teugn Talents 1.7.3 · Appweite mobile Verbesserungen

Version: **1.7.3+188**. Veröffentlichung am 8. September 2026 auf ausdrücklichen Nutzerwunsch.

## Inhalt

Appweite Anpassung der Dialoge und Auswahllisten an kleine Displays, große Schrift und Bildschirmtastaturen; kompakte Teamorganisation und Familiennavigation; überarbeitete Datenschutz-, Support- und Hilfeansichten; korrigierte Funktionssuche und Spielerwechsel. Mitfahrbuchungen für Eltern selbst und ihre Kinder bleiben enthalten.

## Validierung vor Veröffentlichung

- 715 Flutter-Tests bestanden, einschließlich 84 zusätzlicher mobiler Szenarien.
- Flutter Analyze ohne Befunde und Web-Release-Build erfolgreich.
- Umfang, Bereichsmatrix und Bildnachweise: [Appweite mobile Prüfung](MOBILE-APP-PRUEFUNG-2026-09-08.md).
- Veröffentlichung über die bestehenden Abläufe für Web, Backend und signierte APK auf MagentaCloud. Keine Veröffentlichung auf Google Play; native Apple-Veröffentlichung bleibt optional.

## Öffentliche Abnahme

Ausgelieferter Quellstand: `7740ccf213e71bfe5c58660696c374bb6e94c288`.

- [Backend-Auslieferung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34213277199): erfolgreich.
- [Web-Auslieferung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34213277143): erfolgreich. Die öffentliche Versionsdatei bestätigt **1.7.3, Build 188**.
- [Release-Prüfung und Android-Veröffentlichung](https://github.com/tbauer-oss/FC-Teugn/actions/runs/34213277038): erfolgreich; 715 Flutter-Tests, Codeanalyse, Web-Build und signierte APK bestanden. Backend-Tests (272 plus drei vorgeschaltete Tests), Datenbankintegration und HTTP-E2E ebenfalls erfolgreich.

Nachweise: `artifacts/release-1.7.3-build-188/`.


### Öffentliche Prüfung und direktes Android-Update

- [Web-App](https://fcteugnapp.vercel.app): **1.7.3, Build 188** öffentlich bestätigt.
- Backend erreichbar; geschützte Route verweigert anonymen Zugriff mit 401. Die datenbankgestützte Prüfung einer synthetischen ungültigen Einladung liefert erwartungsgemäß 410.
- [MagentaCloud-Download](https://magentacloud.de/s/xkgHEESdKbQ6XMP): APK und Update-Manifest **1.7.3+188** veröffentlicht. Das öffentliche Manifest stimmt mit dem Artefakt des erfolgreichen CI-Laufs überein.
- Vollständiger öffentlicher Download: **92.482.906 Bytes**. SHA-256: `f439d3eabcca365ade90ac04558452c89022c19eed91f89df0e6bd78fc876cca`.
- APK-Signatur gültig und unverändert derselbe Vereinsschlüssel; Paketversion **1.7.3, Code 188** bestätigt.
- Öffentlich heruntergeladene APK im isolierten Android-Emulator direkt über **1.7.2+187** installiert. Der ursprüngliche Installationszeitpunkt bleibt erhalten; App startet und läuft weiter. Kein App-Absturz im Crash-Protokoll.
- Keine Tests mit privaten Geräten oder echten Konten; keine zusätzliche Push-Auslieferungsprüfung in diesem reinen Oberflächenrelease.

Belege: `live-verification.json`, `android-update-verification.json`, `android-signature.txt`, `android-package.txt`, `android-crash-log.txt`, `android-start.png`, CI-Protokoll und das veröffentlichte APK unter `artifacts/release-1.7.3-build-188/`.
