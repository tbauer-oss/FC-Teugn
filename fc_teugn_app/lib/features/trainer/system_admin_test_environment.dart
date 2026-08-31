import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

enum _TestArea { overview, matchday, responses, messages }

enum _DemoResponse { open, accepted, declined }

class SystemAdminTestEnvironmentPage extends StatefulWidget {
  const SystemAdminTestEnvironmentPage({super.key});

  @override
  State<SystemAdminTestEnvironmentPage> createState() =>
      _SystemAdminTestEnvironmentPageState();
}

class _SystemAdminTestEnvironmentPageState
    extends State<SystemAdminTestEnvironmentPage> {
  _TestArea _area = _TestArea.overview;
  bool _matchLive = false;
  bool _matchFinished = false;
  int _homeScore = 0;
  int _awayScore = 0;
  final List<String> _tickerEvents = [];
  final Map<String, _DemoResponse> _responses = {
    'Mia Mustermann': _DemoResponse.accepted,
    'Noah Beispiel': _DemoResponse.open,
    'Emil Testspieler': _DemoResponse.declined,
    'Lina Demo': _DemoResponse.accepted,
  };
  final TextEditingController _messageController = TextEditingController();
  final List<String> _localMessages = [];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _area = _TestArea.overview;
      _matchLive = false;
      _matchFinished = false;
      _homeScore = 0;
      _awayScore = 0;
      _tickerEvents.clear();
      _responses
        ..clear()
        ..addAll({
          'Mia Mustermann': _DemoResponse.accepted,
          'Noah Beispiel': _DemoResponse.open,
          'Emil Testspieler': _DemoResponse.declined,
          'Lina Demo': _DemoResponse.accepted,
        });
      _localMessages.clear();
      _messageController.clear();
    });
  }

  void _startOrFinishMatch() {
    setState(() {
      if (_matchFinished) {
        _matchFinished = false;
        _matchLive = false;
        _homeScore = 0;
        _awayScore = 0;
        _tickerEvents.clear();
        return;
      }
      if (!_matchLive) {
        _matchLive = true;
        _tickerEvents.insert(0, 'Anpfiff · Testspiel gestartet');
      } else {
        _matchLive = false;
        _matchFinished = true;
        _tickerEvents.insert(
          0,
          'Abpfiff · SV Musterhausen $_awayScore:$_homeScore FC Teugn',
        );
      }
    });
  }

  void _addGoal({required bool home}) {
    if (!_matchLive || _matchFinished) return;
    setState(() {
      if (home) {
        _homeScore += 1;
        _tickerEvents.insert(0, 'Tor für FC Teugn · Mia Mustermann');
      } else {
        _awayScore += 1;
        _tickerEvents.insert(0, 'Tor für SV Musterhausen');
      }
    });
  }

  void _publishLocalMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    setState(() {
      _localMessages.insert(0, message);
      _messageController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.appColors.canvas,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const ValueKey('system-admin-local-test-environment'),
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TestHero(onReset: _reset),
                  const SizedBox(height: 14),
                  _TestAreaNavigation(
                    selected: _area,
                    onSelected: (area) => setState(() => _area = area),
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: switch (_area) {
                      _TestArea.overview => _Overview(
                          key: const ValueKey('test-overview'),
                          onOpen: (area) => setState(() => _area = area),
                        ),
                      _TestArea.matchday => _buildMatchday(context),
                      _TestArea.responses => _buildResponses(context),
                      _TestArea.messages => _buildMessages(context),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatchday(BuildContext context) {
    final status = _matchFinished
        ? 'Beendet'
        : _matchLive
            ? 'LIVE'
            : 'Bereit zum Test';
    return _TestCard(
      key: const ValueKey('test-matchday'),
      title: 'Test-Spieltag & Liveticker',
      subtitle: 'Alle Aktionen bleiben ausschließlich auf diesem Gerät.',
      icon: Icons.sports_soccer_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF171918), Color(0xFF5B5000)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Text(
                  status,
                  style: TextStyle(
                    color:
                        _matchLive ? const Color(0xFFFFE600) : Colors.white70,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: _ScoreTeam(label: 'FC Teugn E1', icon: 'FC'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '$_homeScore : $_awayScore',
                        key: const ValueKey('local-test-score'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Expanded(
                      child: _ScoreTeam(
                        label: 'SV Musterhausen',
                        icon: 'SV',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('local-test-match-toggle'),
                onPressed: _startOrFinishMatch,
                icon: Icon(
                  _matchFinished
                      ? Icons.restart_alt_rounded
                      : _matchLive
                          ? Icons.sports_score_rounded
                          : Icons.play_arrow_rounded,
                ),
                label: Text(
                  _matchFinished
                      ? 'Neuer Test'
                      : _matchLive
                          ? 'Abpfiff testen'
                          : 'Liveticker starten',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _matchLive ? () => _addGoal(home: true) : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tor FC Teugn'),
              ),
              OutlinedButton.icon(
                onPressed: _matchLive ? () => _addGoal(home: false) : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tor Gegner'),
              ),
            ],
          ),
          if (_tickerEvents.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Lokaler Verlauf',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final event in _tickerEvents)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LocalResultTile(
                  icon: Icons.bolt_rounded,
                  text: event,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildResponses(BuildContext context) {
    return _TestCard(
      key: const ValueKey('test-responses'),
      title: 'Test-Rückmeldungen',
      subtitle: 'Statuswechsel werden nur im Arbeitsspeicher simuliert.',
      icon: Icons.fact_check_outlined,
      child: Column(
        children: [
          for (final entry in _responses.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.appColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.appColors.outline),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 520;
                    final name = Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: context.appColors.brandSoft,
                          foregroundColor: context.appColors.text,
                          child: Text(
                            entry.key.split(' ').map((part) => part[0]).join(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    );
                    final controls = Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final response in _DemoResponse.values)
                          ChoiceChip(
                            label: Text(_responseLabel(response)),
                            selected: entry.value == response,
                            onSelected: (_) => setState(
                              () => _responses[entry.key] = response,
                            ),
                          ),
                      ],
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [name, const SizedBox(height: 10), controls],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: name),
                        const SizedBox(width: 12),
                        controls,
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessages(BuildContext context) {
    return _TestCard(
      key: const ValueKey('test-messages'),
      title: 'Test-Mitteilungen',
      subtitle: 'Keine Push-Nachricht und keine E-Mail verlässt das Gerät.',
      icon: Icons.notifications_none_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('local-test-message-input'),
            controller: _messageController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Lokale Testmitteilung',
              hintText: 'Zum Beispiel: Treffpunkt wurde geändert',
              prefixIcon: Icon(Icons.edit_note_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('local-test-message-publish'),
              onPressed: _publishLocalMessage,
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('Nur lokal anzeigen'),
            ),
          ),
          if (_localMessages.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final message in _localMessages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LocalResultTile(
                  icon: Icons.campaign_outlined,
                  text: message,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _responseLabel(_DemoResponse response) => switch (response) {
      _DemoResponse.open => 'Offen',
      _DemoResponse.accepted => 'Zugesagt',
      _DemoResponse.declined => 'Abgesagt',
    };

class _TestHero extends StatelessWidget {
  const _TestHero({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.appColors.brandSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.appWarning.withValues(alpha: .45)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.science_rounded),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'LOKALES TESTLABOR',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: .7,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Sicher ausprobieren – ohne Produktivdaten',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Spieltag, Rückmeldungen und Mitteilungen werden mit fiktiven Daten ausschließlich auf diesem Gerät simuliert.',
                  style: TextStyle(color: context.appColors.textMuted),
                ),
              ],
            );
            final reset = OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Testdaten zurücksetzen'),
            );
            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [copy, const SizedBox(height: 14), reset],
              );
            }
            return Row(
              children: [
                Expanded(child: copy),
                const SizedBox(width: 18),
                reset,
              ],
            );
          },
        ),
      );
}

class _TestAreaNavigation extends StatelessWidget {
  const _TestAreaNavigation({
    required this.selected,
    required this.onSelected,
  });

  final _TestArea selected;
  final ValueChanged<_TestArea> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final area in _TestArea.values) ...[
              ChoiceChip(
                key: ValueKey('local-test-area-${area.name}'),
                avatar: Icon(_areaIcon(area), size: 18),
                label: Text(_areaLabel(area)),
                selected: area == selected,
                onSelected: (_) => onSelected(area),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );
}

class _Overview extends StatelessWidget {
  const _Overview({super.key, required this.onOpen});

  final ValueChanged<_TestArea> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 840
              ? 3
              : constraints.maxWidth >= 560
                  ? 2
                  : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              _OverviewTile(
                width: width,
                icon: Icons.sports_soccer_rounded,
                title: 'Spieltag testen',
                description: 'Liveticker starten, Tore erfassen und abpfeifen.',
                onTap: () => onOpen(_TestArea.matchday),
              ),
              _OverviewTile(
                width: width,
                icon: Icons.fact_check_outlined,
                title: 'Rückmeldungen testen',
                description: 'Fiktive Zu- und Absagen gefahrlos ändern.',
                onTap: () => onOpen(_TestArea.responses),
              ),
              _OverviewTile(
                width: width,
                icon: Icons.notifications_none_rounded,
                title: 'Mitteilungen testen',
                description: 'Vorschau ohne Push, E-Mail oder Empfänger.',
                onTap: () => onOpen(_TestArea.messages),
              ),
            ],
          );
        },
      );
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.width,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Material(
          color: context.appColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: context.appColors.outline),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: context.appWarning, size: 28),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: TextStyle(color: context.appColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Öffnen',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.appColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.appColors.brandSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: context.appColors.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(color: context.appColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      );
}

class _ScoreTeam extends StatelessWidget {
  const _ScoreTeam({required this.label, required this.icon});

  final String label;
  final String icon;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.yellow,
            foregroundColor: AppColors.black,
            child:
                Text(icon, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
}

class _LocalResultTile extends StatelessWidget {
  const _LocalResultTile({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.appColors.successSoft,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: context.appSuccess),
            const SizedBox(width: 9),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

String _areaLabel(_TestArea area) => switch (area) {
      _TestArea.overview => 'Übersicht',
      _TestArea.matchday => 'Spieltag',
      _TestArea.responses => 'Rückmeldungen',
      _TestArea.messages => 'Mitteilungen',
    };

IconData _areaIcon(_TestArea area) => switch (area) {
      _TestArea.overview => Icons.dashboard_outlined,
      _TestArea.matchday => Icons.sports_soccer_rounded,
      _TestArea.responses => Icons.fact_check_outlined,
      _TestArea.messages => Icons.notifications_none_rounded,
    };
