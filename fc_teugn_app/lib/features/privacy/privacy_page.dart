import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/providers.dart';
import '../shared/page_scaffold.dart';

class PrivacyPage extends ConsumerStatefulWidget {
  const PrivacyPage({super.key});

  @override
  ConsumerState<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends ConsumerState<PrivacyPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _adminRequests = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final requests = await ref.read(repositoryProvider).privacyRequests();
      final canAdmin = ref
              .read(organizationProvider)
              .valueOrNull
              ?.can('MANAGE_ORGANIZATION') ??
          false;
      final adminRequests = canAdmin
          ? await ref.read(repositoryProvider).adminPrivacyRequests()
          : const <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _requests = requests;
          _adminRequests = adminRequests;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reviewAdminRequest(
    Map<String, dynamic> request,
    String action,
  ) async {
    final user = request['user'] as Map<String, dynamic>? ?? const {};
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action == 'complete'
            ? '${user['name']} anonymisieren?'
            : action == 'reject'
                ? 'Antrag ablehnen'
                : 'Prüfung beginnen'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (action == 'complete')
                const Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: Text(
                    'Diese Aktion widerruft alle Sitzungen, entfernt aktive Zuordnungen '
                    'und ersetzt Identitäts- und Kontaktdaten dauerhaft.',
                  ),
                ),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Prüfvermerk / Begründung'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action == 'complete' ? 'Anonymisieren' : 'Speichern'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      controller.dispose();
      return;
    }
    try {
      final repository = ref.read(repositoryProvider);
      if (action == 'complete') {
        await repository.completeAccountErasure(
          requestId: request['id'] as String,
          reviewNote: controller.text.trim(),
        );
      } else {
        await repository.reviewPrivacyRequest(
          requestId: request['id'] as String,
          status: action == 'reject' ? 'REJECTED' : 'IN_REVIEW',
          reviewNote: controller.text.trim(),
        );
      }
      await _load();
      _message('Datenschutzantrag wurde aktualisiert.');
    } on DioException catch (error) {
      _message(
          _apiMessage(error) ?? 'Antrag konnte nicht aktualisiert werden.');
    } finally {
      controller.dispose();
    }
  }

  Future<void> _export() async {
    try {
      final data = await ref.read(repositoryProvider).exportPersonalData();
      final formatted = const JsonEncoder.withIndent('  ').convert(data);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ihre personenbezogenen Daten'),
          content: SizedBox(
            width: 760,
            height: MediaQuery.sizeOf(context).height * .65,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  formatted,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: formatted));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export wurde kopiert.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('JSON kopieren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
    } on DioException catch (error) {
      _message(
          _apiMessage(error) ?? 'Datenexport konnte nicht erstellt werden.');
    }
  }

  Future<void> _requestErasure() async {
    final result = await showDialog<_ErasureDraft>(
      context: context,
      builder: (_) => const _ErasureDialog(),
    );
    if (result == null) return;
    try {
      await ref.read(repositoryProvider).requestAccountErasure(
            confirmation: result.confirmation,
            reason: result.reason,
          );
      await _load();
      _message('Ihr Löschantrag wurde sicher erfasst.');
    } on DioException catch (error) {
      _message(
          _apiMessage(error) ?? 'Löschantrag konnte nicht erfasst werden.');
    }
  }

  String? _apiMessage(DioException error) {
    final data = error.response?.data;
    return data is Map<String, dynamic> ? data['message'] as String? : null;
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final openRequest = _requests.any(
      (request) =>
          request['type'] == 'ERASURE' &&
          ['RECEIVED', 'IN_REVIEW'].contains(request['status']),
    );
    return PageScaffold(
      title: 'Datenschutz & Ihre Daten',
      subtitle:
          'Transparenz, Einwilligungen und Betroffenenrechte sicher verwalten.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PrivacyOverviewHero(),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 720
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: width,
                    child: _PrivacyActionCard(
                      icon: Icons.download_for_offline_outlined,
                      color: AppColors.blue,
                      title: 'Auskunft & Datenkopie',
                      description:
                          'Die gespeicherten Kontodaten und rechtmäßig verknüpften Kinderdaten als strukturierte Kopie einsehen.',
                      buttonLabel: 'Datenkopie erstellen',
                      onPressed: _export,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _PrivacyActionCard(
                      icon: Icons.person_off_outlined,
                      color: AppColors.orange,
                      title: 'Löschung beantragen',
                      description:
                          'Der Verein prüft den Antrag, bestehende Aufbewahrungspflichten und Rechte Dritter und dokumentiert das Ergebnis.',
                      buttonLabel: openRequest
                          ? 'Antrag wird geprüft'
                          : 'Löschung beantragen',
                      onPressed: openRequest ? null : _requestErasure,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          Text('Ihre Anträge', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (_loading)
            const Center(
              child: LogoLoadingPanel(
                message: 'Datenschutzdaten werden geladen …',
              ),
            )
          else if (_requests.isEmpty)
            const EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'Keine offenen Datenschutzanträge',
              message:
                  'Ihre Daten bleiben durch Rollen, Teamgrenzen und Auditprotokolle geschützt.',
            )
          else
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < _requests.length; index++) ...[
                    _RequestTile(request: _requests[index]),
                    if (index < _requests.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 22),
          if (_adminRequests.isNotEmpty) ...[
            Text('Datenschutzanträge des Vereins',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  for (var index = 0;
                      index < _adminRequests.length;
                      index++) ...[
                    _AdminRequestTile(
                      request: _adminRequests[index],
                      onReview: () =>
                          _reviewAdminRequest(_adminRequests[index], 'review'),
                      onReject: () =>
                          _reviewAdminRequest(_adminRequests[index], 'reject'),
                      onComplete: () => _reviewAdminRequest(
                          _adminRequests[index], 'complete'),
                    ),
                    if (index < _adminRequests.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],
          const PrivacyInformationCenter(),
        ],
      ),
    );
  }
}

class _PrivacyOverviewHero extends StatelessWidget {
  const _PrivacyOverviewHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171A18), Color(0xFF4D4300)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.yellow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.privacy_tip_outlined, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DATENSCHUTZ-CENTER · FC TEUGN TALENTS',
                      style: TextStyle(
                        color: AppColors.yellow,
                        fontSize: 10,
                        letterSpacing: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Ihre Daten. Ihre Rechte. Klar erklärt.',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Informationen in verständlicher Form sowie direkter Zugriff auf Datenkopie und Löschantrag.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PrivacyHeroBadge(
                icon: Icons.block_rounded,
                label: 'Keine Werbung',
              ),
              _PrivacyHeroBadge(
                icon: Icons.lock_person_outlined,
                label: 'Rollenbasierter Zugriff',
              ),
              _PrivacyHeroBadge(
                icon: Icons.child_care_rounded,
                label: 'Schutz Minderjähriger',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyHeroBadge extends StatelessWidget {
  const _PrivacyHeroBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.yellow, size: 17),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
}

class PrivacyInformationCenter extends StatelessWidget {
  const PrivacyInformationCenter({super.key});

  static final Uri _complaintUri =
      Uri.parse('https://www.lda.bayern.de/de/beschwerde.html');

  Future<void> _contactClub() => launchUrl(
        Uri(
          scheme: 'mailto',
          path: 'fcteugn@web.de',
          queryParameters: const {
            'subject': 'Datenschutzanfrage · FC Teugn Talents',
          },
        ),
      );

  Future<void> _openComplaint() => launchUrl(
        _complaintUri,
        mode: LaunchMode.externalApplication,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Transparenz & Betroffenenrechte',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        const Text(
          'Die folgenden Informationen ergänzen die zweckbezogenen Einwilligungen und Datenschutzhinweise in der App.',
        ),
        const SizedBox(height: 10),
        const _PrivacyDisclosure(
          icon: Icons.account_balance_outlined,
          title: 'Verantwortlicher & Datenschutzkontakt',
          initiallyExpanded: true,
          children: [
            _PrivacyParagraph(
              title: 'Verantwortlicher',
              text: 'FC Teugn e.V. · Kreutweg 14 · 93356 Teugn',
            ),
            _PrivacyParagraph(
              title: 'Kontakt für Datenschutzanliegen',
              text:
                  'E-Mail: fcteugn@web.de. Bitte keine Gesundheitsdaten oder Ausweiskopien unverschlüsselt per E-Mail senden.',
            ),
            _PrivacyParagraph(
              title: 'Bearbeitungsfrist',
              text:
                  'Anträge werden grundsätzlich innerhalb eines Monats beantwortet. Bei komplexen oder zahlreichen Anträgen kann die Frist begründet um bis zu zwei Monate verlängert werden. Zur sicheren Zuordnung darf ein Identitätsnachweis verlangt werden.',
            ),
          ],
        ),
        const _PrivacyDisclosure(
          icon: Icons.hub_outlined,
          title: 'Welche Daten werden wofür verarbeitet?',
          children: [
            _PrivacyParagraph(
              title: 'Zwecke',
              text:
                  'Kontoverwaltung, Mannschafts- und Saisonorganisation, Termine und Rückmeldungen, Trainings- und Spielbetrieb, Kommunikation, Pushbenachrichtigungen, Berechtigungen, Einwilligungsnachweise, Support sowie IT-Sicherheit und Missbrauchsprävention.',
            ),
            _PrivacyParagraph(
              title: 'Datenkategorien',
              text:
                  'Stamm- und Kontaktdaten, Rollen und Teamzuordnungen, sportliche Daten, Termine und Rückmeldungen, Kommunikations- und Supportinhalte, Geräte- und Pushkennungen, Einwilligungen, hochgeladene Dateien sowie sicherheitsrelevante Protokolldaten.',
            ),
            _PrivacyParagraph(
              title: 'Rechtsgrundlagen',
              text:
                  'Je nach Verarbeitung: Vertrag beziehungsweise vereinsbezogene Durchführung (Art. 6 Abs. 1 b DSGVO), rechtliche Pflichten (c), berechtigte Interessen an sicherem und geordnetem Vereinsbetrieb (f) oder freiwillige Einwilligung (a). Besondere Kategorien wie Gesundheitsangaben werden nur mit einer einschlägigen Grundlage, regelmäßig ausdrücklicher Einwilligung nach Art. 9 Abs. 2 a DSGVO, verarbeitet.',
            ),
          ],
        ),
        const _PrivacyDisclosure(
          icon: Icons.storage_outlined,
          title: 'Empfänger, Hosting & Speicherdauer',
          children: [
            _PrivacyParagraph(
              title: 'Interne Empfänger',
              text:
                  'Nur berechtigte Personen erhalten entsprechend ihrer Rolle und Mannschaft Zugriff, zum Beispiel Trainerteam, zuständige Funktionäre oder Systemadministration. Eltern und Spieler sehen ausschließlich freigegebene Inhalte.',
            ),
            _PrivacyParagraph(
              title: 'Technische Empfänger',
              text:
                  'Für Hosting, Datenbank, private Dateien und Pushzustellung können vertraglich eingebundene technische Dienstleister eingesetzt werden. Eine Weitergabe zu Werbung oder ein Verkauf personenbezogener Daten findet nicht statt.',
            ),
            _PrivacyParagraph(
              title: 'Drittlandverarbeitung',
              text:
                  'Soweit ein technischer Dienst eine Verarbeitung außerhalb des Europäischen Wirtschaftsraums erfordert, erfolgt sie nur unter den Voraussetzungen der Art. 44 ff. DSGVO, etwa auf Grundlage eines Angemessenheitsbeschlusses oder geeigneter Garantien. Einzelheiten können beim Verein angefragt werden.',
            ),
            _PrivacyParagraph(
              title: 'Lösch- und Speicherkriterien',
              text:
                  'Daten werden nur so lange gespeichert, wie sie für den jeweiligen Vereins- und Appzweck, Nachweise, IT-Sicherheit oder gesetzliche Pflichten benötigt werden. Danach werden sie gelöscht oder, wenn eine weitere Zuordnung nicht erforderlich ist, anonymisiert. Löschanträge können wegen zwingender Aufbewahrungspflichten oder Rechte Dritter teilweise eingeschränkt sein.',
            ),
          ],
        ),
        const _PrivacyDisclosure(
          icon: Icons.child_friendly_outlined,
          title: 'Kinder, Fotos & sensible Angaben',
          children: [
            _PrivacyParagraph(
              title: 'Besonderer Schutz',
              text:
                  'Informationen für Kinder werden klar und verständlich bereitgestellt. Soweit eine Einwilligung für einen direkt an Kinder gerichteten digitalen Dienst erforderlich ist, wird die Zustimmung der sorgeberechtigten Person entsprechend Art. 8 DSGVO berücksichtigt.',
            ),
            _PrivacyParagraph(
              title: 'Fotos und Gesundheitsangaben',
              text:
                  'Fotos, medizinische Hinweise und Kontaktdaten sind nicht öffentlich. Freiwillige Einwilligungen sind einzeln wählbar und können jederzeit mit Wirkung für die Zukunft widerrufen werden. Eine Ablehnung darf die sportliche Teilnahme nicht benachteiligen.',
            ),
            _PrivacyParagraph(
              title: 'Pushnachrichten',
              text:
                  'Push ist freiwillig und gerätebezogen deaktivierbar. Benachrichtigungen werden nur für relevante Vereins- und Appvorgänge versendet; Gerätekennungen können in den Push-Einstellungen entfernt werden.',
            ),
          ],
        ),
        const _PrivacyDisclosure(
          icon: Icons.gavel_outlined,
          title: 'Ihre Rechte nach der DSGVO',
          children: [
            _PrivacyRight(
              article: 'Art. 15',
              title: 'Auskunft & Datenkopie',
              text:
                  'Erfahren, ob und welche personenbezogenen Daten verarbeitet werden, einschließlich Zwecke, Kategorien, Empfänger und Speicherkriterien.',
            ),
            _PrivacyRight(
              article: 'Art. 16',
              title: 'Berichtigung',
              text: 'Unrichtige oder unvollständige Daten korrigieren lassen.',
            ),
            _PrivacyRight(
              article: 'Art. 17/18',
              title: 'Löschung oder Einschränkung',
              text:
                  'Unter den gesetzlichen Voraussetzungen Löschung verlangen oder die Verarbeitung vorübergehend begrenzen lassen.',
            ),
            _PrivacyRight(
              article: 'Art. 20',
              title: 'Datenübertragbarkeit',
              text:
                  'Bereitgestellte Daten bei automatisierter Verarbeitung auf Grundlage von Einwilligung oder Vertrag in einem strukturierten Format erhalten.',
            ),
            _PrivacyRight(
              article: 'Art. 21',
              title: 'Widerspruch',
              text:
                  'Einer Verarbeitung aus berechtigtem Interesse aus Gründen der eigenen Situation widersprechen.',
            ),
            _PrivacyRight(
              article: 'Art. 7 Abs. 3',
              title: 'Einwilligung widerrufen',
              text:
                  'Eine Einwilligung jederzeit für die Zukunft widerrufen; die vorherige Verarbeitung bleibt rechtmäßig.',
            ),
          ],
        ),
        const _PrivacyDisclosure(
          icon: Icons.smart_toy_outlined,
          title: 'Automatisierung, Sicherheit & Protokolle',
          children: [
            _PrivacyParagraph(
              title: 'Keine ausschließlich automatisierte Entscheidung',
              text:
                  'Sportliche Vorschläge wie Autopilot oder Auswertungen entscheiden nicht verbindlich über Personen. Die Entscheidung und Freigabe bleiben beim Trainerteam. Profiling mit rechtlicher oder ähnlich erheblicher Wirkung findet nicht statt.',
            ),
            _PrivacyParagraph(
              title: 'Schutzmaßnahmen',
              text:
                  'Zugriffe werden durch Anmeldung, Rollen, Mannschaftsgrenzen, private Dateifreigaben und sicherheitsrelevante Protokolle begrenzt. Erforderliche Sitzungs- und Gerätespeicher dienen der Anmeldung und Appfunktion, nicht der Werbung.',
            ),
            _PrivacyParagraph(
              title: 'Anonymisierte Historie',
              text:
                  'Wo Vereins-, Sicherheits- oder Nachweishistorien erhalten bleiben müssen, wird die unmittelbare Identität nach Abschluss einer zulässigen Löschung entfernt oder ersetzt.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          color: AppColors.yellowSoft.withValues(alpha: .45),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 680;
                final content = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Beschwerde bei der Datenschutzaufsicht',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sie können sich nach Art. 77 DSGVO beim Bayerischen Landesamt für Datenschutzaufsicht (BayLDA), Promenade 18, 91522 Ansbach, beschweren. Ein vorheriger Kontakt mit dem Verein ist nicht verpflichtend.',
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _contactClub,
                      icon: const Icon(Icons.mail_outline_rounded),
                      label: const Text('Verein kontaktieren'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _openComplaint,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('BayLDA öffnen'),
                    ),
                  ],
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      content,
                      const SizedBox(height: 14),
                      actions,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 18),
                    actions,
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Rechts- und Informationsstand: August 2026 · DSGVO und BDSG in der jeweils geltenden Fassung. Maßgeblich sind zusätzlich die konkreten Einwilligungs- und Verarbeitungshinweise zum jeweiligen Vorgang.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _PrivacyDisclosure extends StatelessWidget {
  const _PrivacyDisclosure({
    required this.icon,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.yellowSoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: AppColors.gold),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(),
            ...children,
          ],
        ),
      );
}

class _PrivacyParagraph extends StatelessWidget {
  const _PrivacyParagraph({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(text),
          ],
        ),
      );
}

class _PrivacyRight extends StatelessWidget {
  const _PrivacyRight({
    required this.article,
    required this.title,
    required this.text,
  });

  final String article;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 70),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.yellowSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                article,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(text),
                ],
              ),
            ),
          ],
        ),
      );
}

class _AdminRequestTile extends StatelessWidget {
  const _AdminRequestTile({
    required this.request,
    required this.onReview,
    required this.onReject,
    required this.onComplete,
  });
  final Map<String, dynamic> request;
  final VoidCallback onReview;
  final VoidCallback onReject;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final user = request['user'] as Map<String, dynamic>? ?? const {};
    final status = request['status'] as String? ?? 'RECEIVED';
    final closed = status == 'COMPLETED' || status == 'REJECTED';
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const CircleAvatar(child: Icon(Icons.person_remove_outlined)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['name'] as String? ?? 'Unbekannt',
                    style: Theme.of(context).textTheme.titleMedium),
                Text('${user['email'] ?? ''} · $status'),
                if (request['reason'] != null)
                  Text(request['reason'] as String,
                      style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
          if (!closed)
            PopupMenuButton<String>(
              tooltip: 'Antrag bearbeiten',
              onSelected: (value) {
                if (value == 'review') onReview();
                if (value == 'reject') onReject();
                if (value == 'complete') onComplete();
              },
              itemBuilder: (_) => [
                if (status == 'RECEIVED')
                  const PopupMenuItem(
                      value: 'review', child: Text('Prüfung beginnen')),
                const PopupMenuItem(
                    value: 'reject', child: Text('Antrag ablehnen')),
                const PopupMenuItem(
                    value: 'complete', child: Text('Konto anonymisieren')),
              ],
            ),
        ],
      ),
    );
  }
}

class _PrivacyActionCard extends StatelessWidget {
  const _PrivacyActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: .12),
                foregroundColor: color,
                child: Icon(icon),
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 7),
              Text(description),
              const SizedBox(height: 18),
              FilledButton.tonal(
                onPressed: onPressed,
                child: Text(buttonLabel),
              ),
            ],
          ),
        ),
      );
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final status = request['status'] as String? ?? 'RECEIVED';
    final label = switch (status) {
      'IN_REVIEW' => 'In Prüfung',
      'COMPLETED' => 'Abgeschlossen',
      'REJECTED' => 'Abgelehnt',
      _ => 'Eingegangen',
    };
    final createdAt = DateTime.tryParse(request['createdAt'] as String? ?? '');
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: const Text('Antrag auf Kontolöschung'),
      subtitle: Text(
        '${createdAt == null ? '' : '${createdAt.day}.${createdAt.month}.${createdAt.year} · '}$label'
        '${request['reviewNote'] == null ? '' : '\n${request['reviewNote']}'}',
      ),
      trailing: Chip(label: Text(label)),
    );
  }
}

class _ErasureDialog extends StatefulWidget {
  const _ErasureDialog();

  @override
  State<_ErasureDialog> createState() => _ErasureDialogState();
}

class _ErasureDialogState extends State<_ErasureDialog> {
  final _formKey = GlobalKey<FormState>();
  final _confirmation = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _confirmation.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Kontolöschung beantragen'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nach Prüfung wird Ihr Konto anonymisiert und Sie werden auf allen Geräten abgemeldet. '
                  'Schreiben Sie zur Bestätigung exakt KONTO LÖSCHEN.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmation,
                  decoration: const InputDecoration(
                      labelText: 'Sicherheitsbestätigung'),
                  validator: (value) => value == 'KONTO LÖSCHEN'
                      ? null
                      : 'Bitte exakt KONTO LÖSCHEN eingeben.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reason,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Hinweis (optional)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                _ErasureDraft(
                  confirmation: _confirmation.text,
                  reason:
                      _reason.text.trim().isEmpty ? null : _reason.text.trim(),
                ),
              );
            },
            child: const Text('Antrag verbindlich senden'),
          ),
        ],
      );
}

class _ErasureDraft {
  const _ErasureDraft({required this.confirmation, this.reason});
  final String confirmation;
  final String? reason;
}
