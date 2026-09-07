# iPhone-Auslieferung und native Build-Prüfung

Die veröffentlichte Web-App kann auf dem iPhone über Safari zum Home-Bildschirm
hinzugefügt werden. Die Installationsseite in der App erklärt die Schritte und
erhält den Rückweg zu einer Mannschaftseinladung.

Das native iOS-Projekt verwendet `de.fcteugn.jugend` und den Anzeigenamen
„FC Teugn Talents“. Das Deploymentziel ist auf iOS 15 abgestimmt. Sämtliche
eingesetzten iOS-Plugins unterstützen Swift Package Manager; Flutter 3.44
integriert diese beim nativen Build automatisch. Eine zusätzliche Podfile ist
deshalb nicht erforderlich. Die eingesetzten Firebase-Apple-Komponenten benötigen eine aktuelle
Xcode-Installation; die CI verwendet dafür den GitHub-Runner `macos-26`.
Quellen: [Firebase Apple Setup](https://firebase.google.com/docs/ios/setup),
[GitHub-Runner](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).
Die Paketverwaltung folgt der [Flutter-Anleitung für Swift Package Manager](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers).

## Reproduzierbare Kompilierung

Im Workflow `Validate FC Teugn Talents` ist bei manuellen Läufen `check_ios`
standardmäßig aktiviert. Er baut mit Flutter 3.44.8 eine native Simulator-App
und speichert `fc-teugn-talents-ios-simulator` als ZIP-Artefakt. Dafür sind keine
Apple-Signaturdaten erforderlich. Ein erfolgreicher Build ist ein Nachweis der
Kompilierbarkeit, keine Geräte- oder App-Store-Abnahme.

Auf einem Mac im Verzeichnis `fc_teugn_app`:

```sh
flutter build ios --simulator --debug --no-codesign
```

## Noch benötigte externe Voraussetzungen

Für TestFlight/App Store fehlen das zugeordnete Apple-Entwicklerteam, die
App-Store-Connect-App und die Signatur-/Provisionierungsdaten. Die Bundle-ID muss
diesem Team zugeordnet werden. Diese Daten dürfen nicht erfunden oder durch
fremde Entwicklerkonten ersetzt werden.

Die bestehende native Push-Implementierung unterstützt Android. Für native
iOS-Push-Mitteilungen sind eine Firebase-Apple-App, deren echte Konfiguration,
APNs-Zugang und die zugehörigen iOS-Capabilities erforderlich; anschließend muss
die plattformspezifische Push-Implementierung ergänzt und auf einem iPhone
abgenommen werden. Die Simulator-Datei wird deshalb nicht als fertige
TestFlight-Version angeboten.

Geräte- und Vereinsabnahme: [Schulungs- und Pilotplan](TALENTS-1.7-SCHULUNG-UND-PILOT.md).
