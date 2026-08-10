import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';

class ContextHelpInfo {
  const ContextHelpInfo({
    required this.summary,
    required this.steps,
    required this.searchQuery,
  });

  final String summary;
  final List<String> steps;
  final String searchQuery;
}

ContextHelpInfo contextHelpFor(String pageTitle, String pageSubtitle) {
  final title = pageTitle.toLowerCase();

  if (title.contains('kinder') || title.contains('rückmeldung')) {
    return const ContextHelpInfo(
      summary:
          'Hier beantwortest du Termine für alle zugeordneten Kinder und siehst den aktuellen Stand sofort.',
      steps: [
        'Oben siehst du, wie viele Antworten offen, zugesagt, vielleicht oder abgesagt sind.',
        'Wähle beim passenden Kind „Zusagen“, „Vielleicht“ oder „Absagen“. Bei einer Absage kannst du freiwillig einen Grund ergänzen.',
        'Die Kalenderansicht wird direkt synchronisiert. Unter „Details“ findest du Termin, Treffpunkt und weitere Informationen.',
      ],
      searchQuery: 'Rückmeldung Vielleicht Absage Grund',
    );
  }
  if (title.contains('liga') || title.contains('gegner')) {
    return const ContextHelpInfo(
      summary:
          'Vereine werden einmal gemeinsam gepflegt; die gegnerischen Mannschaften verwaltest du nur für deine Jugend.',
      steps: [
        'Alle Trainer sehen denselben Vereins-Pool mit Vereinsname, Wappen, Spielstätte und Adresse.',
        'Wähle oben deine Jugend. Öffne einen Verein und füge dort nur die passende Mannschaft wie E1, E2 oder E3 hinzu.',
        'Beim Anlegen eines Spiels wählst du zuerst den Verein und danach die Jugendmannschaft. Fehlt sie, wird sie im berechtigten Jugendbereich automatisch angelegt.',
        'Vereinsdaten und Wappen gelten zentral; Jugendmannschaften können ausschließlich Trainer der jeweiligen Jugend verwalten.',
      ],
      searchQuery: 'Verein Gegner Jugendmannschaft E1 E2 verwalten',
    );
  }
  if (title.contains('kalender') || title.contains('termin')) {
    return const ContextHelpInfo(
      summary:
          'Plane Termine, Teilnehmer, Rückmeldungen und Erinnerungen zentral.',
      steps: [
        'Tippe einen Tag an, um alle Termine dieses Tages vollständig zu sehen.',
        'Beim Anlegen kannst du Mannschaften oder einzelne Personen auswählen.',
        'Bearbeitete Zeiten, Teilnehmer und Erinnerungen werden sofort neu zugeordnet.',
      ],
      searchQuery: 'Termin Kalender anlegen',
    );
  }
  if (title.contains('spiel') ||
      title.contains('match') ||
      title.startsWith('fc teugn ·')) {
    return const ContextHelpInfo(
      summary:
          'Hier verwaltest du Spieldaten, Veröffentlichung, Kader, Aufstellung und Liveticker.',
      steps: [
        'Prüfe zuerst Gegner, Anstoß sowie Treffpunktzeit und Treffpunktort.',
        'Die Erinnerung 24 Stunden vor dem Spiel ist standardmäßig aktiv und kann in den Spieldaten für dieses Spiel ausgeschaltet werden.',
        '„Mit Trainerteam teilen“ informiert ausgewählte Berechtigte; „Für Eltern & Spieler freigeben“ macht das Spiel für Familien sichtbar.',
        'Speichere danach den Kader. Im Autopiloten wählst du „Ausgewogen“, „Einsatzzeit“ oder „Positionstreu“ und prüfst anschließend den Wechselplan. Unter jedem eingewechselten Spieler steht seine geplante Zielposition. Bei „Positionstreu“ kannst du zusätzlich festlegen, dass ausgewechselte Startspieler später bevorzugt auf ihren ursprünglichen Stammplatz zurückkehren.',
        'Am Spieltag steuerst du Uhr, Tore und Wechsel. Nach Abpfiff bewertest du die nominierten Spieler im trainerinternen Reiter „Bewertung“.',
      ],
      searchQuery: 'Spiel Erinnerung 24 Stunden Trainerteam teilen Treffpunkt',
    );
  }
  if (title.contains('training')) {
    return const ContextHelpInfo(
      summary:
          'Plane Trainingszeiten, Inhalte, Plätze und automatische Erinnerungen.',
      steps: [
        'Wähle Mannschaft und Trainingstermin im aktuellen Kontext.',
        'Ergänze Übungen, Dauer und Hinweise für das Trainerteam.',
        'Prüfe bei Platzänderungen die angezeigten Überschneidungen.',
      ],
      searchQuery: 'Training planen Erinnerung',
    );
  }
  if (title.contains('spieler') || title.contains('team')) {
    return const ContextHelpInfo(
      summary:
          'Verwalte Spielerprofile, Mannschaftszuordnung, Nummern und Positionen.',
      steps: [
        'Nutze die Mannschaftsauswahl, um nur den gewünschten Kader zu sehen.',
        'Öffne ein Profil für Stammdaten, Positionen und Statistiken. Bei Torhütern und Verteidigern erscheint dort zusätzlich „Spiele zu null“.',
        'Änderungen gelten nur im aktuell ausgewählten Jugend- und Mannschaftskontext.',
      ],
      searchQuery: 'Spieler Team Profil Mannschaft',
    );
  }
  if (title.contains('nachricht') || title.contains('mitteilung')) {
    return const ContextHelpInfo(
      summary:
          'Sende gezielte Mitteilungen und optional eine Push-Benachrichtigung.',
      steps: [
        'Wähle zuerst Mannschaften und Empfängergruppe.',
        'Aktiviere Push nur, wenn die Nachricht sofort auf den Geräten erscheinen soll.',
        'Lesestatus und Antworten findest du direkt bei der Mitteilung.',
      ],
      searchQuery: 'Nachricht Mitteilung Push',
    );
  }
  if (title.contains('statistik')) {
    return const ContextHelpInfo(
      summary:
          'Werte Einsätze, Tore, Assists und trainerinterne Leistungsentwicklungen aus.',
      steps: [
        'Wähle Saison, Jugend und Mannschaft für den gewünschten Vergleich.',
        'Die Daten werden aus abgeschlossenen Spielen übernommen.',
        'Das Leistungszentrum zeigt ausschließlich Trainern Durchschnitt, letzte Bewertungen und Trends – niemals als öffentliche Rangliste.',
        'Öffne Spielerwerte für detaillierte Auswertungen.',
      ],
      searchQuery: 'Statistiken Leistungszentrum Bewertungen',
    );
  }
  if (title.contains('datenschutz')) {
    return const ContextHelpInfo(
      summary:
          'Verwalte Einwilligungen, Datenexport und Löschanfragen nachvollziehbar.',
      steps: [
        'Prüfe den aktuellen Stand der Einwilligungen.',
        'Fordere bei Bedarf einen persönlichen Datenexport an.',
        'Löschanträge werden protokolliert und von Berechtigten bearbeitet.',
      ],
      searchQuery: 'Datenschutz Einwilligung Export Löschung',
    );
  }
  if (title.contains('mitglied') || title.contains('freigabe')) {
    return const ContextHelpInfo(
      summary:
          'Prüfe Registrierungen, Rollen, Mannschaftszugriffe und bestehende Konten zentral.',
      steps: [
        'Neue Registrierungen werden vor der Freigabe einer Rolle und Mannschaft zugeordnet.',
        'Systemadministratoren verwalten individuelle Rechte und sichere Zugangslinks.',
        'Ein Konto lässt sich über das rote Löschsymbol dauerhaft entfernen; dafür muss ausdrücklich „LÖSCHEN“ eingegeben werden.',
      ],
      searchQuery: 'Mitglieder Freigaben Rollen Konto löschen',
    );
  }
  if (title.contains('verein') || title.contains('organisation')) {
    return const ContextHelpInfo(
      summary:
          'Verwalte Vereinsstruktur, Mannschaften, Rollen und Saisonkontext.',
      steps: [
        'Prüfe vor Änderungen immer die aktuell ausgewählte Jugend und Saison.',
        'Berechtigungen begrenzen, welche Verwaltungsbereiche sichtbar sind.',
        'Größere Saisonänderungen zeigen vor dem Speichern eine Vorschau.',
      ],
      searchQuery: 'Verein Mannschaft Rolle Saison',
    );
  }
  if (title.contains('aufgabe') || title.contains('ausrüstung')) {
    return const ContextHelpInfo(
      summary: 'Organisiere Aufgaben, Material und wiederkehrende Checklisten.',
      steps: [
        'Lege Verantwortliche und Fälligkeit eindeutig fest.',
        'Nutze Vorlagen für regelmäßig wiederkehrende Abläufe.',
        'Erledigte Punkte bleiben für das Team nachvollziehbar.',
      ],
      searchQuery: 'Aufgaben Ausrüstung Checklisten',
    );
  }
  if (title.contains('support')) {
    return const ContextHelpInfo(
      summary:
          'Melde technische Probleme mit den Angaben, die für eine schnelle Lösung nötig sind.',
      steps: [
        'Beschreibe, was du unmittelbar vor dem Fehler gemacht hast.',
        'Füge nach Möglichkeit einen Screenshot und den betroffenen Bereich hinzu.',
        'Antworten und Statusänderungen erscheinen direkt im Supportfall.',
      ],
      searchQuery: 'Technischer Support Problem melden',
    );
  }

  return ContextHelpInfo(
    summary: pageSubtitle,
    steps: const [
      'Prüfe oben den aktuell ausgewählten Jugend- und Mannschaftskontext.',
      'Öffne Einträge für Details oder nutze die hervorgehobenen Aktionen.',
      'Weitere Schritt-für-Schritt-Anleitungen findest du in Hilfe & FAQ.',
    ],
    searchQuery: pageTitle,
  );
}

class ContextHelpButton extends StatelessWidget {
  const ContextHelpButton({
    super.key,
    required this.pageTitle,
    required this.pageSubtitle,
  });

  final String pageTitle;
  final String pageSubtitle;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
        tooltip: 'Hilfe zu diesem Bereich',
        visualDensity: VisualDensity.compact,
        onPressed: () => _showContextHelp(context),
        icon: const Icon(Icons.help_outline_rounded, size: 21),
      );

  Future<void> _showContextHelp(BuildContext context) async {
    final info = contextHelpFor(pageTitle, pageSubtitle);
    final route = GoRouterState.of(context).uri.path;
    final helpRoute =
        route.startsWith('/parent') ? '/parent/help' : '/trainer/help';
    final openFullHelp = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ContextHelpSheet(
        pageTitle: pageTitle,
        info: info,
      ),
    );
    if (openFullHelp != true || !context.mounted) return;
    context.push(
      '$helpRoute?topic=${Uri.encodeQueryComponent(info.searchQuery)}',
    );
  }
}

class _ContextHelpSheet extends StatelessWidget {
  const _ContextHelpSheet({required this.pageTitle, required this.info});

  final String pageTitle;
  final ContextHelpInfo info;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(22, 12, 22, 22 + bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.yellowSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.help_outline_rounded),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hilfe zu diesem Bereich',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          Text(
                            pageTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Schließen',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(info.summary,
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 18),
                for (var index = 0; index < info.steps.length; index++) ...[
                  _HelpStep(number: index + 1, text: info.steps[index]),
                  if (index != info.steps.length - 1)
                    const SizedBox(height: 10),
                ],
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.menu_book_rounded),
                  label: const Text('Ausführliche Hilfe & FAQ öffnen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.black,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: AppColors.yellow,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(child: Text(text)),
        ],
      );
}
