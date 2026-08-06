# Responsive-Audit – 6. August 2026

## Prüfmethodik

- **A**: neue automatisierte Responsive-Widgettests ohne Flutter- oder
  RenderFlex-Exception; zentrale Texte und Aktionen werden zusätzlich vermessen.
- **B**: bereits bestehender zielgerichteter Widgettest der jeweiligen Ansicht.
- **C**: nachvollziehbare Codeprüfung auf feste Breiten/Höhen, starre `Row`s,
  Scrollbarkeit, SafeArea und lokale statt globale Breitenentscheidungen.
- **–**: in diesem Durchlauf nicht als eigenständige Ansicht automatisiert.

Ein erfolgreicher Build allein wird nicht als Prüfung markiert.

## Automatisierte Viewport-Matrix

`AdaptiveActionBar` wird bei Textskalierung 100 %, 115 %, 130 % und 150 % in
allen folgenden Größen gerendert und auf vollständig innerhalb des Viewports
liegende Aktionen geprüft:

- 320 × 568
- 360 × 640
- 375 × 667
- 390 × 844
- 412 × 915
- 480 × 800
- 600 × 960
- 673 × 841 (Foldable innen)
- 841 × 673 (Querformat)
- 1280 × 720 (Web)

Die Kaderansicht wird zusätzlich bei 320 × 568, 390 × 844, 673 × 841,
841 × 673 und 1280 × 720 jeweils mit 100 % und 150 % Text getestet. Enthalten
sind E1/E2, „Alle Mannschaften“, ein langer Spielername, mehrere Spieler, alle
vier Aktionen sowie eine dynamische Größenänderung von 320 auf 673 und danach
auf 841 Pixel Breite.

Die individuellen Rechte werden bei 320 × 568, 673 × 841 und 1280 × 720 jeweils
mit 100 % und 150 % Text geprüft. Kategorien, lange Rechtebezeichnungen,
Rollenstandard, individuelle Freigabe, individueller Entzug, Scrollbarkeit,
Reset und Schließen sind enthalten. Ein eigener Test simuliert zusätzlich ein
vertikales Foldable-Scharnier.

## Hauptseiten-Matrix

| Bereich | 320 px | 390 px | Fold geschlossen | Fold offen | Querformat | Text 150 % | Evidenz |
|---|---:|---:|---:|---:|---:|---:|---|
| Dashboard | C | B+C | C | C | C | C | Dashboard-Fehlerzustand und zentrale Karten |
| Kader | A | A | A | A | A | A | `match_squad_responsive_test.dart` |
| Aufstellung | C | B+C | C | B+C | C | C | Aufstellungs- und Autopilot-Tests |
| Liveticker | C | B+C | C | C | C | C | UI-Vertrag, Uhr- und Offline-Tests |
| Kalender | C | B+C | C | C | C | C | Monatsnavigation, Terminmodell und Mobile-Tests |
| Termine | C | B+C | C | C | C | C | responsive Formularbasis, Termin-/Rückmeldetests |
| Spieler/Profile | C | B+C | C | C | C | B+C | mobile Profil- und Spielerliste-Tests |
| Mitglieder | C | B+C | C | C | C | C | Listen-Codeprüfung und adaptive Dialogbasis |
| Individuelle Rechte | A | A | A | A | A | A | `member_permissions_dialog_responsive_test.dart` |
| Liga und Gegner | C | C | C | C | C | C | Dialog-/Tabellen-Codeprüfung, Import-Modelltests |
| Nachrichten | C | B+C | C | C | C | C | Rollen-/Zugriffstests und Dialog-Codeprüfung |
| Training/Plätze | C | B+C | C | C | C | C | Mobile-Belegungs- und Resilienztests |
| Organisation/Aufgaben | C | C | C | C | C | C | Karten-, Dialog- und Modellprüfung |
| Hilfe/FAQ | C | B+C | C | C | C | C | Mobile- und Webbreiten-Widgettests |

## Strukturelle Befunde und Korrekturen

1. **Kader:** Eine `Row` gab dem Status nur die nach vier breiten Aktionen
   verbleibende Breite. Die Aktionen sind nun ein eigener adaptiver Bereich und
   die gesamte Ansicht eine vertikal scrollbar aufgebaute Liste. Bei weniger
   als 480 Pixeln wird der Mannschaftsfilter zum vollbreiten Dropdown.
2. **Spielerzeilen:** Rückmeldesteuerung und Checkbox engen den Namen nicht mehr
   gemeinsam ein. Der Name erhält die vollständige Inhaltsbreite und maximal
   zwei sinnvolle Zeilen; Status und Mannschaft stehen darunter in einem `Wrap`.
3. **Individuelle Rechte:** Das feste 720-Pixel-Dialoglayout und
   `ListTile.trailing` wurden entfernt. Mobil wird ein Vollbilddialog verwendet;
   jede Berechtigung wechselt anhand ihrer lokalen Breite zwischen Zeile und
   Spalte. Nur der Inhalt scrollt, Kopf und Aktionen bleiben erreichbar.
4. **Zentrale Komponenten:** Breakpoints, adaptive Aktionsleisten und adaptive
   Dialoge liegen in `adaptive_layout.dart`. `ResponsiveFormDialog` und
   `PageScaffold` verwenden diese gemeinsame Grundlage beziehungsweise dieselben
   Breakpoints.
5. **Foldables:** Layoutentscheidungen werden in `LayoutBuilder` bei jedem
   Größenwechsel neu getroffen. Gemeldete vertikale Display-Features werden im
   adaptiven Dialog als nicht nutzbarer Trennbereich behandelt.
6. **Bestehende feste Dialogbreiten:** Feste Wunschbreiten innerhalb eines
   Flutter-`AlertDialog` wurden einzeln gesucht. Sie sind durch die
   Dialog-Inset-Constraints begrenzt; die beiden tatsächlich breitenverdrängenden
   Konstruktionen wurden strukturell ersetzt. Langformulare verwenden bereits
   beziehungsweise nun den gemeinsamen mobilen Vollbilddialog.

## Bewusst nicht behauptet

Die mit **C** markierten Ansichten wurden im Code geprüft, aber in diesem
Durchlauf nicht für jede einzelne Zelle als vollständige End-to-End-Seite auf
einem realen Gerät bedient. Reale Samsung-Fold-Gerätetests bleiben deshalb eine
zusätzliche Freigabestufe; die beschriebenen Viewports, Größenwechsel und
Scharnierdaten werden automatisiert simuliert.
