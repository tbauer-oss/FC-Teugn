import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_theme.dart';
import '../../core/models/support.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';

class SupportPage extends ConsumerStatefulWidget {
  const SupportPage({super.key, this.initialTicketId});
  final String? initialTicketId;

  @override
  ConsumerState<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends ConsumerState<SupportPage> {
  bool _initialTicketOpened = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final administrator = user?.role == UserRole.superAdmin;
    final tickets = ref.watch(supportTicketsProvider);
    return PageScaffold(
      title: administrator
          ? 'Technischer Support · Eingang'
          : 'Technischer Support',
      subtitle: administrator
          ? 'Anfragen prüfen, beantworten und nachvollziehbar abschließen.'
          : 'Wir helfen dir direkt bei Bedienung, Darstellung oder technischen Problemen.',
      action: FilledButton.icon(
        onPressed: () => _showNewTicket(context, ref),
        icon: const Icon(Icons.add_comment_rounded),
        label: const Text('Anfrage stellen'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SupportHero(administrator: administrator),
          const SizedBox(height: 16),
          tickets.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Card(
              child: ListTile(
                leading: const Icon(Icons.sync_problem_rounded),
                title: const Text(
                    'Support-Anfragen konnten nicht geladen werden.'),
                subtitle: Text('$error'),
                trailing: IconButton(
                  tooltip: 'Erneut laden',
                  onPressed: () => ref.invalidate(supportTicketsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
            ),
            data: (items) {
              final initialTicket = widget.initialTicketId == null
                  ? null
                  : items.cast<SupportTicketModel?>().firstWhere(
                        (ticket) => ticket?.id == widget.initialTicketId,
                        orElse: () => null,
                      );
              if (!_initialTicketOpened && initialTicket != null) {
                _initialTicketOpened = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _showTicket(context, ref, initialTicket, administrator);
                  }
                });
              }
              return items.isEmpty
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          children: [
                            Icon(Icons.support_agent_rounded,
                                size: 52, color: context.appSuccess),
                            const SizedBox(height: 12),
                            Text(
                              administrator
                                  ? 'Aktuell liegen keine Support-Anfragen vor.'
                                  : 'Du hast noch keine Support-Anfrage gestellt.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final ticket in items)
                            _TicketTile(
                              ticket: ticket,
                              administrator: administrator,
                              onTap: () => _showTicket(
                                  context, ref, ticket, administrator),
                            ),
                        ],
                      ),
                    );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showNewTicket(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _NewTicketDialog(),
    );
    if (created == true) ref.invalidate(supportTicketsProvider);
  }

  Future<void> _showTicket(
    BuildContext context,
    WidgetRef ref,
    SupportTicketModel ticket,
    bool administrator,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _TicketDialog(ticket: ticket, administrator: administrator),
    );
    ref.invalidate(supportTicketsProvider);
  }
}

class _SupportHero extends StatelessWidget {
  const _SupportHero({required this.administrator});
  final bool administrator;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.navy, AppColors.blue],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: context.appWarning,
              foregroundColor: AppColors.navy,
              child: const Icon(Icons.support_agent_rounded, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    administrator
                        ? 'Support-Zentrale'
                        : 'Schnell und nachvollziehbar Hilfe bekommen',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    administrator
                        ? 'Antworten, interne Notizen und Statusänderungen bleiben vollständig dokumentiert.'
                        : 'Beschreibe kurz, was du tun wolltest und was stattdessen passiert ist. Ein Screenshot hilft oft.',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: .78)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({
    required this.ticket,
    required this.administrator,
    required this.onTap,
  });
  final SupportTicketModel ticket;
  final bool administrator;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          backgroundColor:
              _statusColor(context, ticket.status).withValues(alpha: .14),
          foregroundColor: _statusColor(context, ticket.status),
          child: const Icon(Icons.confirmation_number_outlined),
        ),
        title: Text(ticket.subject,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text([
          if (administrator && ticket.creatorName.isNotEmpty)
            ticket.creatorName,
          ticket.category.label,
          ticket.status.label,
          '${ticket.updatedAt.day}.${ticket.updatedAt.month}.${ticket.updatedAt.year}',
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right_rounded),
      );
}

class _NewTicketDialog extends ConsumerStatefulWidget {
  const _NewTicketDialog();
  @override
  ConsumerState<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends ConsumerState<_NewTicketDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  final _appArea = TextEditingController();
  SupportCategory _category = SupportCategory.usage;
  PlatformFile? _attachment;
  bool _contactRequested = false;
  bool _pushEnabled = true;
  bool _saving = false;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    _appArea.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
      withData: true,
    );
    if (result != null && mounted) {
      setState(() => _attachment = result.files.single);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final package = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      await ref.read(repositoryProvider).createSupportTicket(
            category: _category,
            subject: _subject.text.trim(),
            description: _description.text.trim(),
            appArea: _appArea.text.trim(),
            contactRequested: _contactRequested,
            pushEnabled: _pushEnabled,
            technicalMetadata: {
              'appVersion': package.version,
              'buildNumber': package.buildNumber,
              'platform':
                  kIsWeb ? 'WEB' : defaultTargetPlatform.name.toUpperCase(),
              'windowSize': '${size.width.round()}x${size.height.round()}',
              'occurredAt': DateTime.now().toUtc().toIso8601String(),
            },
            attachmentBytes: _attachment?.bytes,
            attachmentName: _attachment?.name,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Anfrage konnte nicht gesendet werden: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Technische Anfrage stellen'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<SupportCategory>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Kategorie'),
                    items: [
                      for (final item in SupportCategory.values)
                        DropdownMenuItem(value: item, child: Text(item.label)),
                    ],
                    onChanged: (value) =>
                        setState(() => _category = value ?? _category),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _subject,
                    decoration: const InputDecoration(labelText: 'Betreff'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Bitte Betreff eingeben.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    minLines: 5,
                    maxLines: 9,
                    decoration: const InputDecoration(
                      labelText: 'Was ist passiert?',
                      hintText:
                          'Was wolltest du tun? Was ist stattdessen passiert?',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Bitte Problem beschreiben.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _appArea,
                    decoration: const InputDecoration(
                      labelText: 'App-Bereich (optional)',
                      hintText: 'z. B. Kalender oder Liveticker',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _contactRequested,
                    onChanged: (value) =>
                        setState(() => _contactRequested = value),
                    title: const Text('Rückkontakt erwünscht'),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _pushEnabled,
                    onChanged: (value) => setState(() => _pushEnabled = value),
                    title: const Text(
                        'Systemadministration zusätzlich per Push informieren'),
                    subtitle: const Text(
                        'Die Anfrage erscheint in jedem Fall im Support-Eingang.'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.privacy_tip_outlined),
                    title: Text('Automatisch mitgesendet'),
                    subtitle: Text(
                      'App-Version, Build, Plattform, Fenstergröße und Zeitpunkt. '
                      'Keine Passwörter, Anmelde- oder Push-Tokens.',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickAttachment,
                    icon: const Icon(Icons.attach_file_rounded),
                    label: Text(
                        _attachment?.name ?? 'Screenshot oder PDF anhängen'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: const Text('Senden'),
          ),
        ],
      );
}

class _TicketDialog extends ConsumerStatefulWidget {
  const _TicketDialog({required this.ticket, required this.administrator});
  final SupportTicketModel ticket;
  final bool administrator;

  @override
  ConsumerState<_TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends ConsumerState<_TicketDialog> {
  late SupportTicketModel _ticket = widget.ticket;
  final _reply = TextEditingController();
  bool _internal = false;
  bool _pushEnabled = true;
  bool _saving = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reply.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final ticket = await ref.read(repositoryProvider).replySupportTicket(
            ticketId: _ticket.id,
            body: _reply.text.trim(),
            internal: _internal,
            pushEnabled: _pushEnabled,
          );
      if (mounted) {
        setState(() {
          _ticket = ticket;
          _reply.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeStatus(SupportStatus status) async {
    final ticket = await ref.read(repositoryProvider).updateSupportStatus(
          ticketId: _ticket.id,
          status: status,
        );
    if (mounted) setState(() => _ticket = ticket);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_ticket.subject),
        content: SizedBox(
          width: 720,
          height: MediaQuery.sizeOf(context).height * .68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(_ticket.category.label)),
                  Chip(label: Text(_ticket.status.label)),
                  if (widget.administrator)
                    DropdownButton<SupportStatus>(
                      value: _ticket.status,
                      items: [
                        for (final status in SupportStatus.values)
                          DropdownMenuItem(
                              value: status, child: Text(status.label))
                      ],
                      onChanged: (value) {
                        if (value != null) _changeStatus(value);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(_ticket.description),
              const Divider(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    for (final message in _ticket.messages)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: message.internal
                              ? context.appWarning.withValues(alpha: .13)
                              : AppColors.navy.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${message.authorName}${message.internal ? ' · Interne Notiz' : ''}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(message.body),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              TextField(
                controller: _reply,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                    labelText: widget.administrator && _internal
                        ? 'Interne Notiz'
                        : 'Antwort'),
              ),
              if (widget.administrator)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _internal,
                  onChanged: (value) =>
                      setState(() => _internal = value ?? false),
                  title: const Text('Nur intern sichtbar'),
                ),
              if (!_internal)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _pushEnabled,
                  onChanged: (value) => setState(() => _pushEnabled = value),
                  title: const Text('Zusätzlich als Pushnachricht senden'),
                  subtitle: const Text(
                      'Die Antwort wird immer in der App gespeichert.'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen')),
          FilledButton.icon(
              onPressed: _saving ? null : _send,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Antworten')),
        ],
      );
}

Color _statusColor(BuildContext context, SupportStatus status) =>
    switch (status) {
      SupportStatus.open => context.appWarning,
      SupportStatus.inProgress => context.appInfo,
      SupportStatus.question => Colors.deepPurple,
      SupportStatus.resolved => context.appSuccess,
      SupportStatus.closed => context.appColors.textMuted,
    };
