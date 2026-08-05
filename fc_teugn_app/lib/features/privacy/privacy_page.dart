import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                      title: 'Datenexport',
                      description:
                          'Alle Daten Ihres Kontos und rechtmäßig verknüpfter Kinder als strukturiertes JSON einsehen und kopieren.',
                      buttonLabel: 'Daten jetzt exportieren',
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
                          'Der Verein prüft gesetzliche Aufbewahrungspflichten und anonymisiert das Konto anschließend nachvollziehbar.',
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
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.teal),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'FC Teugn verwendet keine Werbe- oder Tracking-SDKs für Kinder. '
                      'Medizinische Hinweise, Kontaktdaten und Fotos sind nicht öffentlich. '
                      'Audit- und Vereinshistorie werden bei einer Löschung nur in anonymisierter Form erhalten.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
