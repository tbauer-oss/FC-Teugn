import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/club_logo.dart';
import '../shared/page_scaffold.dart';

enum HelpCategory {
  all('Alle Themen', Icons.auto_awesome_rounded),
  start('Erste Schritte', Icons.rocket_launch_rounded),
  calendar('Kalender', Icons.calendar_month_rounded),
  team('Spieler & Team', Icons.groups_rounded),
  matchday('Spielbetrieb', Icons.sports_soccer_rounded),
  training('Training', Icons.fitness_center_rounded),
  communication('Nachrichten', Icons.forum_rounded),
  organization('Organisation', Icons.account_tree_rounded),
  privacy('Datenschutz', Icons.shield_outlined);

  const HelpCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum HelpAudience { everyone, staff, family }

class HelpArticle {
  const HelpArticle({
    required this.category,
    required this.title,
    required this.summary,
    required this.steps,
    this.keywords = const [],
    this.audience = HelpAudience.everyone,
    this.route,
    this.routeLabel,
    this.tip,
  });

  final HelpCategory category;
  final String title;
  final String summary;
  final List<String> steps;
  final List<String> keywords;
  final HelpAudience audience;
  final String? route;
  final String? routeLabel;
  final String? tip;

  bool isVisibleFor(bool staffView) => switch (audience) {
        HelpAudience.everyone => true,
        HelpAudience.staff => staffView,
        HelpAudience.family => !staffView,
      };

  bool matches(String query) {
    if (query.isEmpty) return true;
    final searchable = [
      title,
      summary,
      category.label,
      ...steps,
      ...keywords,
    ].join(' ').toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .every(searchable.contains);
  }
}

class HelpPage extends StatefulWidget {
  const HelpPage({
    super.key,
    required this.staffView,
    this.initialQuery,
  });

  final bool staffView;
  final String? initialQuery;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  late final TextEditingController _searchController;
  HelpCategory _category = HelpCategory.all;
  late String _query;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery?.trim() ?? '';
    _searchController = TextEditingController(text: _query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<HelpArticle> get _visibleArticles => helpArticles
      .where((article) => article.isVisibleFor(widget.staffView))
      .toList();

  List<HelpArticle> get _filteredArticles => _visibleArticles.where((article) {
        final categoryMatches =
            _category == HelpCategory.all || article.category == _category;
        return categoryMatches && article.matches(_query.trim());
      }).toList();

  String _roleRoute(String suffix) =>
      widget.staffView ? '/trainer$suffix' : '/parent$suffix';

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredArticles;
    final categoryCounts = {
      for (final category in HelpCategory.values)
        category: category == HelpCategory.all
            ? _visibleArticles.length
            : _visibleArticles
                .where((article) => article.category == category)
                .length,
    };

    return PageScaffold(
      title: 'Hilfe & FAQ',
      showContextHelp: false,
      subtitle: widget.staffView
          ? 'Anleitungen für Trainer, Betreuung und Vereinsverwaltung.'
          : 'Schnelle Antworten für Eltern und Spieler.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HelpHero(
            staffView: widget.staffView,
            controller: _searchController,
            query: _query,
            articleCount: _visibleArticles.length,
            onChanged: (value) => setState(() => _query = value),
            onClear: _clearSearch,
          ),
          const SizedBox(height: 18),
          Text('Direkt loslegen',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          _QuickHelpGrid(
            actions: widget.staffView
                ? [
                    _QuickHelpAction(
                      icon: Icons.swap_horiz_rounded,
                      title: 'Mannschaft wechseln',
                      caption: 'Arbeitsbereich verstehen',
                      onTap: () => _showArticle(
                        context,
                        _articleNamed(
                            'Wie wechsle ich Jugend oder Mannschaft?'),
                      ),
                    ),
                    _QuickHelpAction(
                      icon: Icons.calendar_month_rounded,
                      title: 'Termin planen',
                      caption: 'Kalender öffnen',
                      onTap: () => context.go('/trainer/events'),
                    ),
                    _QuickHelpAction(
                      icon: Icons.sports_soccer_rounded,
                      title: 'Spieltag',
                      caption: 'Kader und Liveticker',
                      onTap: () => context.go('/trainer/matches'),
                    ),
                    _QuickHelpAction(
                      icon: Icons.forum_rounded,
                      title: 'Nachrichten',
                      caption: 'Mitteilung versenden',
                      onTap: () => context.go('/trainer/messages'),
                    ),
                  ]
                : [
                    _QuickHelpAction(
                      icon: Icons.how_to_reg_rounded,
                      title: 'Rückmeldung',
                      caption: 'Zu- oder absagen',
                      onTap: () => context.go('/parent/events'),
                    ),
                    _QuickHelpAction(
                      icon: Icons.groups_rounded,
                      title: 'Meine Kinder',
                      caption: 'Profile ansehen',
                      onTap: () => context.go('/parent/players'),
                    ),
                    _QuickHelpAction(
                      icon: Icons.sports_soccer_rounded,
                      title: 'Spiele',
                      caption: 'Kader und Liveticker',
                      onTap: () => context.go('/parent/matches'),
                    ),
                    _QuickHelpAction(
                      icon: Icons.notifications_active_rounded,
                      title: 'Pushnachrichten',
                      caption: 'Aktivierung und Ziele',
                      onTap: () => _showArticle(
                        context,
                        _articleNamed('Wie aktiviere ich Pushnachrichten?'),
                      ),
                    ),
                  ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Themen durchsuchen',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                '${filtered.length} ${filtered.length == 1 ? 'Antwort' : 'Antworten'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final category in HelpCategory.values)
                  if ((categoryCounts[category] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(category.icon, size: 17),
                        label: Text(
                          '${category.label} · ${categoryCounts[category]}',
                        ),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Keine passende Antwort gefunden',
              message:
                  'Versuche einen kürzeren Suchbegriff oder zeige wieder alle Themen an.',
              action: FilledButton.icon(
                onPressed: () => setState(() {
                  _category = HelpCategory.all;
                  _searchController.clear();
                  _query = '';
                }),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Suche zurücksetzen'),
              ),
            )
          else
            _ArticleList(
              articles: filtered,
              queryActive: _query.trim().isNotEmpty,
              routeFor: (article) {
                final route = article.route;
                if (route == null) return null;
                return route.startsWith('/trainer') ||
                        route.startsWith('/parent')
                    ? route
                    : _roleRoute(route);
              },
            ),
          const SizedBox(height: 20),
          _ContactCard(
            staffView: widget.staffView,
            onOpenMessages: () => context.go(_roleRoute('/messages')),
          ),
        ],
      ),
    );
  }

  HelpArticle _articleNamed(String title) =>
      _visibleArticles.firstWhere((article) => article.title == title);

  Future<void> _showArticle(
    BuildContext context,
    HelpArticle article,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: _ArticleContent(
            article: article,
            route: article.route == null
                ? null
                : article.route!.startsWith('/trainer') ||
                        article.route!.startsWith('/parent')
                    ? article.route
                    : _roleRoute(article.route!),
            closeBeforeNavigation: true,
          ),
        ),
      ),
    );
  }
}

class _HelpHero extends StatelessWidget {
  const _HelpHero({
    required this.staffView,
    required this.controller,
    required this.query,
    required this.articleCount,
    required this.onChanged,
    required this.onClear,
  });

  final bool staffView;
  final TextEditingController controller;
  final String query;
  final int articleCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171A18), Color(0xFF4D4300)],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const ClubLogo(size: 50),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FC TEUGN TALENTS · HILFECENTER',
                      style: TextStyle(
                        color: AppColors.yellow,
                        fontSize: 10,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Was möchtest du erledigen?',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                              ),
                    ),
                    Text(
                      '$articleCount geprüfte Antworten · ${staffView ? 'Trainer & Verwaltung' : 'Familie & Team'}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .68),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Semantics(
            textField: true,
            label: 'FAQ durchsuchen',
            child: TextField(
              key: const ValueKey('help-search-field'),
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Zum Beispiel „Kader“, „Rückmeldung“ oder „Push“',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Suche löschen',
                        onPressed: onClear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickHelpAction {
  const _QuickHelpAction({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;
}

class _QuickHelpGrid extends StatelessWidget {
  const _QuickHelpGrid({required this.actions});

  final List<_QuickHelpAction> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: AppColors.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: action.onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.yellowSoft,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(action.icon, color: AppColors.black),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(action.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                Text(
                                  action.caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ArticleList extends StatelessWidget {
  const _ArticleList({
    required this.articles,
    required this.queryActive,
    required this.routeFor,
  });

  final List<HelpArticle> articles;
  final bool queryActive;
  final String? Function(HelpArticle article) routeFor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final article in articles) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: ValueKey('help-${article.category.name}-${article.title}'),
              initiallyExpanded: queryActive && articles.length <= 3,
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.yellowSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(article.category.icon,
                    color: AppColors.black, size: 21),
              ),
              title: Text(article.title,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                article.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                _ArticleContent(
                  article: article,
                  route: routeFor(article),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _ArticleContent extends StatelessWidget {
  const _ArticleContent({
    required this.article,
    required this.route,
    this.closeBeforeNavigation = false,
  });

  final HelpArticle article;
  final String? route;
  final bool closeBeforeNavigation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (closeBeforeNavigation) ...[
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.yellowSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(article.category.icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(article.title,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(article.summary),
          const SizedBox(height: 12),
        ],
        for (var index = 0; index < article.steps.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 25,
                  height: 25,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.black,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: AppColors.yellow,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(article.steps[index])),
              ],
            ),
          ),
        if (article.tip != null) ...[
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.yellowSoft.withValues(alpha: .62),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    size: 20, color: AppColors.gold),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    article.tip!,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (route != null) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () {
                if (closeBeforeNavigation) Navigator.of(context).pop();
                context.go(route!);
              },
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(article.routeLabel ?? 'Bereich öffnen'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.staffView,
    required this.onOpenMessages,
  });

  final bool staffView;
  final VoidCallback onOpenMessages;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Noch nicht gelöst?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                staffView
                    ? 'Nutze das Mitteilungscenter für die Abstimmung mit Vereinsleitung oder Trainerteam.'
                    : 'Schreibe deinem Trainerteam direkt über das Mitteilungscenter.',
                style: TextStyle(color: Colors.white.withValues(alpha: .7)),
              ),
            ],
          );
          final button = FilledButton.icon(
            onPressed: onOpenMessages,
            icon: const Icon(Icons.forum_rounded),
            label: const Text('Nachrichten öffnen'),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [text, const SizedBox(height: 14), button],
            );
          }
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 18),
              button,
            ],
          );
        },
      ),
    );
  }
}

const helpArticles = <HelpArticle>[
  HelpArticle(
    category: HelpCategory.start,
    title: 'Wie wechsle ich Jugend oder Mannschaft?',
    summary:
        'Der Arbeitsbereich begrenzt alle Listen und Aktionen auf die gewählte Jugend und Mannschaft.',
    audience: HelpAudience.staff,
    keywords: ['E1', 'E2', 'Arbeitsbereich', 'Teamwechsel', 'Jugend'],
    steps: [
      'Tippe oben auf die aktuell angezeigte Jugend beziehungsweise Mannschaft.',
      'Wähle zuerst genau eine Jugend und anschließend eine Mannschaft oder „Alle Mannschaften dieser Jugend“.',
      'Bestätige die Auswahl. Dashboard, Spieler, Kalender, Spiele und Statistiken wechseln gemeinsam in diesen Kontext.',
    ],
    tip:
        'Trainer und Co-Trainer sehen nur freigegebene Mannschaften. Vereins- und Systemrollen können je nach Berechtigung weiter wechseln.',
  ),
  HelpArticle(
    category: HelpCategory.start,
    title: 'Wie finde ich mich in der App zurecht?',
    summary:
        'Die Hauptbereiche sind nach Mannschaft, Spieltag, Kommunikation und Verwaltung gegliedert.',
    keywords: ['Menü', 'Navigation', 'Zurück', 'Mehr', 'Startseite'],
    steps: [
      'Auf dem Handy erreichst du Start, Team, Kalender und Spiele über die untere Leiste.',
      'Unter „Mehr“ findest du alle weiteren Bereiche einschließlich Hilfe und Datenschutz.',
      'Auf Detailseiten führt der dezente Zurück-Bereich sicher zur passenden Übersicht zurück.',
      'Im Web stehen dieselben Bereiche dauerhaft links in der Seitenleiste.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.start,
    title: 'Wie aktualisiere ich Daten und App?',
    summary:
        'Die App aktualisiert Inhalte automatisch und prüft beim Start auf eine neue Android-Version.',
    keywords: ['Update', 'APK', 'neu laden', 'MagentaCloud', 'aktualisieren'],
    steps: [
      'Ziehe eine Seite auf dem Handy nach unten, um die aktuellen Vereinsdaten neu zu laden.',
      'Eine neue Android-Version wird beim Start automatisch gemeldet und kann direkt installiert werden.',
      'Erlaube bei der ersten Aktualisierung gegebenenfalls die Installation aus dieser App.',
      'In der Webversion genügt bei einem neuen Release ein vollständiges Neuladen der Seite.',
    ],
    tip:
        'Während einer laufenden Eingabe nicht neu laden. Warte zuerst auf die Speicherbestätigung.',
  ),
  HelpArticle(
    category: HelpCategory.start,
    title: 'Wie richte ich FC Teugn Talents auf dem iPhone als App ein?',
    summary:
        'Über Safari wird die Web-App mit eigenem Symbol installiert; danach kann sie auch Pushnachrichten empfangen.',
    keywords: [
      'iPhone',
      'iOS',
      'Safari',
      'Home-Bildschirm',
      'Web-App',
      'installieren',
      'Push'
    ],
    route: '/messages',
    routeLabel: 'Push-Einstellungen öffnen',
    steps: [
      'Aktualisiere das iPhone mindestens auf iOS 16.4 und öffne https://fcteugnapp.vercel.app ausdrücklich in Safari.',
      'Melde dich an, tippe in Safari auf „Teilen“ und anschließend auf „Zum Home-Bildschirm“. Fehlt der Eintrag, wähle unten „Aktionen bearbeiten“ und aktiviere ihn.',
      'Lass „Als Web-App öffnen“ eingeschaltet, bestätige den Namen „FC Teugn Talents“ und tippe oben auf „Hinzufügen“.',
      'Schließe den Safari-Tab und starte die App künftig ausschließlich über das neue FC-Teugn-Symbol auf dem Home-Bildschirm.',
      'Öffne in der App „Mehr“ → „Nachrichten & Abstimmung“ → „Einstellungen“ und tippe dort auf „Push aktivieren“.',
      'Bestätige die Einwilligung in der App und erlaube anschließend auch die iOS-Abfrage „Mitteilungen erlauben“.',
      'Prüfe unter iPhone „Einstellungen“ → „Mitteilungen“ → „FC Teugn Talents“, ob Mitteilungen, Sperrbildschirm, Mitteilungszentrale, Banner, Töne und Kennzeichen aktiviert sind.',
    ],
    tip:
        'Die Push-Freigabe funktioniert auf dem iPhone nur aus der installierten Home-Bildschirm-Web-App und muss durch deinen Tipp auf „Push aktivieren“ ausgelöst werden. Beim Antippen einer Meldung öffnet sich direkt die App beziehungsweise der passende Bereich.',
  ),
  HelpArticle(
    category: HelpCategory.start,
    title: 'Was passiert ohne Internetverbindung?',
    summary:
        'Unterstützte Änderungen werden vorgemerkt und bei stabiler Verbindung automatisch übertragen.',
    keywords: ['offline', 'synchronisieren', 'Verbindung', 'Warteschlange'],
    steps: [
      'Die App zeigt oberhalb der Seite an, wie viele Änderungen noch auf den Versand warten.',
      'Bleibe angemeldet; die Warteschlange wird bei wiederhergestellter Verbindung automatisch verarbeitet.',
      'Livetickeraktionen behalten ihre Reihenfolge und erzeugen durch ihre eindeutige Kennung keine doppelten Tore.',
      'Prüfe nach der Synchronisierung kurz den sichtbaren Stand.',
    ],
    tip:
        'Korrekturen wie „Letzte Aktion zurück“ benötigen bewusst einen aktuellen Online-Spielstand.',
  ),
  HelpArticle(
    category: HelpCategory.calendar,
    title: 'Wie sehe ich alle Termine eines Tages?',
    summary:
        'Ein Tipp auf den Kalendertag zeigt auch Termine, die in der Monatszelle keinen Platz mehr haben.',
    keywords: ['Monat', 'Tag', 'Popup', 'Agenda', 'Terminliste'],
    route: '/events',
    routeLabel: 'Kalender öffnen',
    steps: [
      'Öffne den Kalender und wähle die Monatsansicht.',
      'Tippe oder klicke auf den gewünschten Tag.',
      'Im kompakten Tagesfenster werden sämtliche Termine chronologisch angezeigt.',
      'Wähle einen Termin aus, um Details und Rückmeldungen zu öffnen.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.calendar,
    title: 'Wie lege ich einen Termin oder eine Serie an?',
    summary:
        'Termine können für Mannschaften oder individuell ausgewählte Personen erstellt werden.',
    audience: HelpAudience.staff,
    keywords: [
      'Termin anlegen',
      'Serie',
      'Training',
      'Erinnerung',
      'Teilnehmer'
    ],
    route: '/events',
    routeLabel: 'Termin planen',
    steps: [
      'Öffne den Kalender und wähle „Termin anlegen“.',
      'Lege Art, Datum, Uhrzeit, Mannschaft und bei Bedarf einzelne Teilnehmende fest.',
      'Aktiviere Rückmeldungen, Frist und eine optionale Push-Erinnerung.',
      'Für regelmäßige Termine aktivierst du die Serie und bestimmst Rhythmus sowie Enddatum.',
      'Speichere erst nach der Zusammenfassung. Änderungen an Zeit oder Datum terminieren Erinnerungen automatisch neu.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.calendar,
    title: 'Wie gebe ich eine Zu- oder Absage ab?',
    summary:
        'Rückmeldungen werden immer für das ausgewählte Kind beziehungsweise Spielerprofil gespeichert.',
    audience: HelpAudience.family,
    keywords: ['Zusage', 'Absage', 'Vielleicht', 'Torhüter', 'Rückmeldung'],
    route: '/events',
    routeLabel: 'Termine öffnen',
    steps: [
      'Öffne den Termin über Kalender, Dashboard oder eine Benachrichtigung.',
      'Wähle bei mehreren Kindern zuerst das richtige Spielerprofil.',
      'Entscheide zwischen „Zugesagt“, „Abgesagt“ oder „Vielleicht“ und ergänze bei Bedarf eine Notiz.',
      'Gib an, ob das Kind als Torhüter verfügbar ist, sofern diese Auswahl angeboten wird.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.calendar,
    title: 'Wie erinnere ich nur offene Rückmeldungen?',
    summary:
        'Erinnerungen erreichen nur relevante Personen, von denen noch keine Antwort vorliegt.',
    audience: HelpAudience.staff,
    keywords: ['offen', 'Erinnerung', 'Push senden', 'Teilnehmer'],
    route: '/events',
    routeLabel: 'Rückmeldungen prüfen',
    steps: [
      'Öffne den Termin und den Abschnitt „Zu- und Absagen“.',
      'Prüfe die offene Anzahl und wähle „Offene Rückmeldungen erinnern“.',
      'Entscheide, ob zusätzlich zur In-App-Nachricht eine Pushnachricht versendet werden soll.',
      'Bei individueller Teilnehmerauswahl werden ausschließlich diese Personen beziehungsweise ihre berechtigten Eltern benachrichtigt.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.calendar,
    title: 'Wie funktionieren Fahrgemeinschaften?',
    summary:
        'Eltern können Fahrten anbieten oder Plätze anfragen; Trainer behalten den Überblick.',
    keywords: ['Fahrt', 'Mitfahrplatz', 'Auto', 'Fahrgemeinschaft'],
    route: '/events',
    routeLabel: 'Kalender öffnen',
    steps: [
      'Öffne den betreffenden Termin und den Bereich „Fahrgemeinschaften“.',
      'Lege ein Fahrangebot mit freien Plätzen, Treffpunkt und Abfahrtszeit an oder frage einen Platz an.',
      'Der Fahrer beziehungsweise ein berechtigter Trainer bestätigt oder lehnt die Anfrage ab.',
      'Telefonnummern sind nur für tatsächlich beteiligte und berechtigte Personen sichtbar.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.team,
    title: 'Wie lege ich einen Spieler an oder bearbeite ihn?',
    summary:
        'Persönliche Daten, Geschlecht, Positionen, Trikotnummer und Teamzuordnung werden im Profil gepflegt.',
    audience: HelpAudience.staff,
    keywords: ['Spieler anlegen', 'm/w/d', 'LM', 'RM', 'Position', 'Profil'],
    route: '/players',
    routeLabel: 'Spieler & Kader öffnen',
    steps: [
      'Öffne „Spieler & Kader“ und wähle „Spieler anlegen“ oder ein bestehendes Profil.',
      'Erfasse Zuordnung und persönliche Angaben einschließlich Geschlecht m/w/d.',
      'Pflege Haupt- und Nebenposition; LM und RM stehen ebenfalls zur Verfügung.',
      'Ergänze Trikotnummer, starken Fuß und Kaderstatus und speichere das Profil.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.team,
    title: 'Wie ordne ich mehrere Kinder einem Elternteil zu?',
    summary:
        'Eine Sorgeberechtigtenbeziehung wird je Kind gespeichert und kann auch jugendübergreifend bestehen.',
    audience: HelpAudience.staff,
    keywords: ['Geschwister', 'Eltern', 'Kinder zuordnen', 'Sorgeberechtigt'],
    route: '/players',
    routeLabel: 'Spielerprofile öffnen',
    steps: [
      'Öffne das erste Spielerprofil und den Abschnitt „Sorgeberechtigte“.',
      'Ordne das gewünschte Elternkonto zu und lege Rechte für Sorge, Abholung und Kommunikation fest.',
      'Wiederhole die Zuordnung im Profil jedes weiteren Geschwisterkindes.',
      'Das Elternkonto zeigt anschließend alle verknüpften Kinder – auch aus unterschiedlichen Jugenden.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.team,
    title: 'Welche Profildaten sind besonders geschützt?',
    summary:
        'Gesundheitsdaten, Notfallkontakte, Dokumente und interne Entwicklungshinweise sind zusätzlich berechtigt.',
    keywords: [
      'Gesundheit',
      'Notfall',
      'Dokumente',
      'Entwicklung',
      'Einwilligung'
    ],
    steps: [
      'Allgemeine Stammdaten sind nur im zugeordneten Teamkontext sichtbar.',
      'Gesundheit, Notfallkontakte und geschützte Dokumente benötigen zusätzliche Berechtigungen.',
      'Eltern sehen ausschließlich ihre verknüpften Kinder; interne Trainerbeobachtungen bleiben verborgen.',
      'Einwilligungen können einzeln dokumentiert und widerrufen werden.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.team,
    title: 'Wie verwalte ich Stammformationen?',
    summary:
        'Grundformationen können angepasst und mit einem verständlichen Suffix als Variante gespeichert werden.',
    audience: HelpAudience.staff,
    keywords: ['Formation', 'Suffix', 'Stammformation', 'Positionen'],
    route: '/team',
    routeLabel: 'Team-Zentrale öffnen',
    steps: [
      'Öffne die Team-Zentrale und wähle „Stammformation“.',
      'Wähle eine Grundformation oder bearbeite eine vorhandene berechtigte Vorlage.',
      'Passe Positionsnamen und Anordnung an und ergänze bei Varianten ein Suffix.',
      'Speichere die Formation dauerhaft als Teamstandard oder nutze sie später nur für einen einzelnen Spieltag.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.matchday,
    title: 'Wie lege ich Gegner, Liga und Spiel an?',
    summary:
        'Gegner werden je Jugend gespeichert und können mit Vereinswappen wiederverwendet werden.',
    audience: HelpAudience.staff,
    keywords: ['Gegner', 'Liga', 'Vereinswappen', 'Spielplan', 'ICS', 'BFV'],
    route: '/matches',
    routeLabel: 'Spielbetrieb öffnen',
    steps: [
      'Öffne im Spielbetrieb „Liga & Gegner“ und lege Liga sowie gegnerische Mannschaften für die aktuelle Jugend an.',
      'Lade beim Gegner ein gut zugeschnittenes Vereinswappen hoch und gib dessen Jugendbezeichnung an.',
      'Wähle beim neuen Spiel den gespeicherten Gegner aus oder füge ihn direkt über das Plus hinzu.',
      'Alternativ importierst du einen geeigneten Spielplan und prüfst die Vorschau vor der Übernahme.',
    ],
    tip:
        'Das FC-Teugn-Wappen wird automatisch verwendet. Gegnerwappen erscheinen im Spieltag und Liveticker, sobald sie im Gegner-Pool gespeichert sind.',
  ),
  HelpArticle(
    category: HelpCategory.matchday,
    title: 'Wie speichere und veröffentliche ich den Kader?',
    summary:
        'Auswahl, Speicherung und Veröffentlichung sind getrennt, damit keine Person versehentlich angefragt wird.',
    audience: HelpAudience.staff,
    keywords: [
      'Kader speichern',
      'nominieren',
      'veröffentlichen',
      'alle auswählen',
      'E1',
      'E2'
    ],
    route: '/matches',
    routeLabel: 'Spieltage öffnen',
    steps: [
      'Öffne den Spieltag und den Reiter „Kader“.',
      'Filtere bei einem gemeinsamen Spielerpool nach E1, E2 oder „Alle Mannschaften“.',
      'Wähle die gewünschten Spieler. „Alle auswählen“ betrifft ausschließlich die gerade sichtbare Auswahl.',
      'Tippe auf „Kader speichern“ und warte auf die Bestätigung.',
      'Erst „Veröffentlichen“ informiert die ausgewählten Spieler beziehungsweise deren Eltern und setzt diese auf offen.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.matchday,
    title: 'Wie erstelle ich Aufstellung und Wechselplan?',
    summary:
        'Die grafische Aufstellung kann frei bearbeitet oder mit dem Autopiloten vorbereitet werden.',
    audience: HelpAudience.staff,
    keywords: [
      'Aufstellung',
      'Autopilot',
      'Startelf',
      'Wechselplan',
      'Kapitän'
    ],
    route: '/matches',
    routeLabel: 'Spieltag auswählen',
    steps: [
      'Speichere zuerst den Spieltagskader.',
      'Öffne „Aufstellung“, wähle die Formation und ziehe Spieler auf ihre Positionen.',
      'Markiere Torhüter und Kapitän und passe Positionsbezeichnungen bei Bedarf an.',
      'Der Autopilot schlägt eine positionsgerechte Startelf und faire Wechsel vor; die Trainerfreigabe bleibt erforderlich.',
      'Veröffentliche die Aufstellung erst, wenn sie für Eltern und Spieler sichtbar werden soll.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.matchday,
    title: 'Wie bediene ich den Liveticker zuverlässig?',
    summary:
        'Die Uhr läuft lokal flüssig; Ereignisse werden geordnet und bei Bedarf offline vorgemerkt.',
    audience: HelpAudience.staff,
    keywords: ['Liveticker', 'Tor', 'Uhr', 'Pause', 'Vollbild', 'offline'],
    route: '/matches',
    routeLabel: 'Spieltage öffnen',
    steps: [
      'Öffne den Spieltag und den Reiter „Liveticker“.',
      'Starte, pausiere oder beende das Spiel über die Steuerung – dieselben Aktionen stehen auch im Vollbild bereit.',
      'Erfasse Tore und weitere Ereignisse. Die App zeigt ausstehende Synchronisierungen sichtbar an.',
      'Bei kurzer Unterbrechung läuft die Uhr ohne Netzruckler weiter und sendet Aktionen anschließend in Originalreihenfolge.',
      'Beende das Spiel erst nach Prüfung des Ergebnisses; daraus werden Statistiken neu berechnet.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.matchday,
    title: 'Was sehen Eltern und Spieler am Spieltag?',
    summary:
        'Nur veröffentlichte Kader und Aufstellungen sowie freigegebene Livetickerinhalte werden angezeigt.',
    audience: HelpAudience.family,
    keywords: ['Kader sehen', 'Aufstellung', 'Liveticker', 'Ergebnis'],
    route: '/matches',
    routeLabel: 'Spiele öffnen',
    steps: [
      'Öffne „Spiele“ und wähle die Begegnung.',
      'Im Infobereich findest du Zeit, Ort, Wettbewerb und Spielzeit.',
      'Kader und Aufstellung erscheinen erst nach der jeweiligen Trainerfreigabe.',
      'Ein freigegebener Liveticker zeigt Uhr, Ergebnis und Verlauf; interne taktische Notizen bleiben verborgen.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.training,
    title: 'Wie plane ich reguläre Trainings und Erinnerungen?',
    summary:
        'Regelmäßige Trainingszeiten und deren Vorlauf werden im Mannschaftskontext verwaltet.',
    audience: HelpAudience.staff,
    keywords: ['reguläres Training', '1 Stunde', '30 Minuten', 'Erinnerung'],
    route: '/training',
    routeLabel: 'Training öffnen',
    steps: [
      'Öffne „Training & Platzplanung“ und die Trainingszeiten.',
      'Lege Wochentag, Beginn, Ende und Ort für die Mannschaft fest.',
      'Wähle die automatische Erinnerung: keine, 30 Minuten, 1 Stunde, 2 Stunden oder benutzerdefiniert.',
      'Die Einstellung gilt für den aktiven Mannschafts- beziehungsweise Jugendkontext und berücksichtigt Europe/Berlin.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.training,
    title: 'Wie erstelle ich einen Trainingsplan?',
    summary:
        'Eine Einheit kann Lernziele, Phasen, Übungen, Material und Anwesenheit enthalten.',
    audience: HelpAudience.staff,
    keywords: ['Übung', 'Trainingsplan', 'Anwesenheit', 'Material'],
    route: '/training',
    routeLabel: 'Trainingsplanung öffnen',
    steps: [
      'Wähle eine planbare Trainingseinheit aus.',
      'Ergänze Schwerpunkt, Lernziele, Trainer, Material und Platzaufteilung.',
      'Ordne Aufwärmen, Hauptteil, Spielform und Abschluss oder nutze Bausteine aus der Übungsbibliothek.',
      'Nach der Einheit erfasst du tatsächliche Anwesenheit und Feedback getrennt von der vorherigen Zusage.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.communication,
    title: 'Wie aktiviere ich Pushnachrichten?',
    summary:
        'Push kann je Gerät aktiviert und pro Nachrichtenkategorie persönlich eingestellt werden.',
    keywords: [
      'Push',
      'Benachrichtigung',
      'Android',
      'Berechtigung',
      'aktivieren'
    ],
    route: '/messages',
    routeLabel: 'Benachrichtigungen öffnen',
    steps: [
      'Bestätige beim ersten Start die Push-Abfrage der App und anschließend die Android- beziehungsweise Browserfreigabe. Auf dem iPhone muss die Seite vorher über Safari zum Home-Bildschirm hinzugefügt worden sein.',
      'Öffne bei Bedarf „Nachrichten & Abstimmung“ und dort „Einstellungen“, um Push pro Kategorie zu aktivieren.',
      'Jedes Gerät wird separat registriert; ein Benutzer kann mehrere Geräte verwenden.',
      'Beim Antippen einer Pushnachricht öffnet sich die App direkt im passenden Kalender, Spieltag oder Mitteilungscenter.',
    ],
    tip:
        'Ist Push in Android dauerhaft abgelehnt, muss die Berechtigung in den Systemeinstellungen der App wieder freigegeben werden.',
  ),
  HelpArticle(
    category: HelpCategory.communication,
    title: 'Wie versende ich eine Mitteilung mit optionalem Push?',
    summary:
        'Mitteilung, Empfänger, Lesebestätigung und Pushversand lassen sich bewusst getrennt festlegen.',
    audience: HelpAudience.staff,
    keywords: ['Mitteilung', 'Push optional', 'Empfänger', 'Lesebestätigung'],
    route: '/messages',
    routeLabel: 'Mitteilung verfassen',
    steps: [
      'Öffne das Mitteilungscenter und wähle „Mitteilung verfassen“.',
      'Bestimme Mannschaften und Zielgruppe oder wähle einzelne Empfänger.',
      'Lege Priorität, Veröffentlichung und optional eine Lesebestätigung fest.',
      'Aktiviere „Push-Benachrichtigung senden“ nur, wenn die Nachricht zusätzlich sofort auf den Geräten erscheinen soll.',
      'Veröffentliche die Mitteilung oder speichere sie als Entwurf beziehungsweise zeitgesteuert.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.communication,
    title: 'Wo finde ich neue Nachrichten und Einstellungen?',
    summary:
        'Dashboard und Mitteilungscenter zeigen ungelesene Inhalte und persönliche Benachrichtigungen.',
    keywords: ['ungelesen', 'Dashboard', 'Einstellungen', 'Nachrichten'],
    route: '/messages',
    routeLabel: 'Mitteilungscenter öffnen',
    steps: [
      'Eine deutlich sichtbare Meldung im Dashboard weist auf neue Nachrichten hin.',
      'Im Mitteilungscenter findest du veröffentlichte Mitteilungen und persönliche Benachrichtigungen.',
      'Öffne einen Eintrag, um ihn zu lesen und gegebenenfalls als gelesen zu markieren.',
      'Unter „Einstellungen“ steuerst du In-App- und Pushnachrichten je Kategorie.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.organization,
    title: 'Wie verwalte ich Aufgaben, Material und Checklisten?',
    summary:
        'Der Bereich unterstützt wiederkehrende Organisation im Mannschaftsalltag.',
    keywords: ['Aufgabe', 'Ausrüstung', 'Material', 'Checkliste', 'Trikot'],
    route: '/operations',
    routeLabel: 'Aufgaben & Ausrüstung öffnen',
    steps: [
      'Lege Aufgaben mit Verantwortlichem, Frist, Status und optionaler Erinnerung an.',
      'Pflege Materialbestand und Ausgaben; Rückgaben bleiben nachvollziehbar gespeichert.',
      'Erstelle Vorlagen für Spieltag, Turnier oder Saisonstart und starte daraus eine Checkliste.',
      'Eltern und Spieler sehen nur die für sie freigegebenen beziehungsweise zugewiesenen Aufgaben.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.organization,
    title: 'Wie funktionieren Freigaben, Rollen und mehrere Teams?',
    summary:
        'Konten werden geprüft, einer Rolle zugeordnet und für eine oder mehrere Mannschaften freigegeben.',
    audience: HelpAudience.staff,
    keywords: ['Freigabe', 'Rolle', 'Trainer', 'Co-Trainer', 'mehrere Teams'],
    route: '/trainer/approvals',
    routeLabel: 'Mitglieder & Freigaben öffnen',
    steps: [
      'Öffne „Mitglieder & Berechtigungen“ und prüfe neue Registrierungen.',
      'Wähle eine zulässige Rolle und die Mannschaftszuordnungen innerhalb der vorgesehenen Jugend.',
      'Trainer und Co-Trainer können dadurch zwischen ihren freigegebenen Mannschaften wechseln.',
      'Vereinsweite Rollen und sensible Rechte dürfen nur mit entsprechender Organisationsberechtigung vergeben werden.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.organization,
    title: 'Wie führe ich einen sicheren Saisonwechsel durch?',
    summary:
        'Der Saisonwechsel besitzt immer eine Vorschau und löscht keine historische Saison.',
    audience: HelpAudience.staff,
    keywords: ['Saisonanfang', 'Saisonwechsel', 'Regelprofil', 'Vorschau'],
    route: '/trainer/organization',
    routeLabel: 'Vereinsverwaltung öffnen',
    steps: [
      'Öffne „Mannschaften & Verein“ und die Vereinsadministration.',
      'Pflege Saisonbeginn taggenau und prüfe die freigegebenen Regelprofile.',
      'Erstelle eine Vorschau für Jugend-, Mannschafts- und Spielerwechsel; dabei werden noch keine Daten verändert.',
      'Führe den Wechsel erst nach vollständiger Prüfung aus. Die Transaktion übernimmt entweder alles oder nichts.',
    ],
    tip:
        'Alte Termine, Ergebnisse, Statistiken und Sorgeberechtigtenbeziehungen bleiben erhalten.',
  ),
  HelpArticle(
    category: HelpCategory.organization,
    title: 'Wie entstehen die Statistiken?',
    summary:
        'Werte werden aus beendeten Spielen, Aufstellungen, Anwesenheiten und gültigen Tickerereignissen berechnet.',
    keywords: [
      'Statistik',
      'Tore',
      'Einsätze',
      'Spiele zu Null',
      'Clean Sheet'
    ],
    route: '/statistics',
    routeLabel: 'Statistiken öffnen',
    steps: [
      'Veröffentliche Aufstellung und erfasse Spielereignisse möglichst vollständig.',
      'Beim Spielende berechnet das System Einsätze, Minuten, Tore, Vorlagen und Mannschaftswerte neu.',
      'Für Torhüter und Verteidiger zählen Spiele ohne Gegentor automatisch als „Spiele zu Null“.',
      'Eltern sehen ausschließlich die zulässigen Werte ihrer verknüpften Kinder; es gibt keine öffentliche Rangliste Minderjähriger.',
    ],
  ),
  HelpArticle(
    category: HelpCategory.privacy,
    title: 'Wo finde ich Datenschutz, Export und Löschantrag?',
    summary: 'Jeder Benutzer erreicht seine Datenrechte direkt in der App.',
    keywords: [
      'Datenschutz',
      'Export',
      'Löschen',
      'Einwilligung',
      'meine Daten'
    ],
    route: '/privacy',
    routeLabel: 'Datenschutz öffnen',
    steps: [
      'Öffne auf dem Handy das Kontomenü oder unter „Mehr“ den Bereich „Datenschutz & Einwilligungen“.',
      'Der Datenexport enthält das eigene Konto und – bei gesetzlicher Vertretung – Daten verknüpfter Kinder.',
      'Ein Löschantrag wird sicher bestätigt und anschließend von einer berechtigten Vereinsrolle geprüft.',
      'Einwilligungen im Spielerprofil können einzeln eingesehen und widerrufen werden.',
    ],
  ),
];
