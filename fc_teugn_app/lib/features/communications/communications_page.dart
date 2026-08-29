import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/models/communication.dart';
import '../../core/models/organization.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../../core/push/native_push_service.dart';
import '../../core/push/push_client.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../auth/auth_controller.dart';
import '../parent/family_assistant_model.dart';
import '../shared/page_scaffold.dart';

class CommunicationsPage extends ConsumerStatefulWidget {
  const CommunicationsPage({
    super.key,
    required this.staffView,
    this.initialSection,
  });

  final bool staffView;
  final String? initialSection;

  @override
  ConsumerState<CommunicationsPage> createState() => _CommunicationsPageState();
}

class _CommunicationsPageState extends ConsumerState<CommunicationsPage> {
  _CommunicationView _view = _CommunicationView.announcements;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _view = switch (widget.initialSection) {
      'contact' => _CommunicationView.familyContact,
      'notifications' => _CommunicationView.notifications,
      'settings' => _CommunicationView.settings,
      _ => _CommunicationView.announcements,
    };
  }

  void _reload() => setState(() => _revision++);

  @override
  Widget build(BuildContext context) {
    final destinations = [
      const _CommunicationDestination(
        view: _CommunicationView.announcements,
        label: 'Mitteilungen',
        description: 'Team-Infos verfassen und verwalten',
        icon: Icons.campaign_rounded,
      ),
      const _CommunicationDestination(
        view: _CommunicationView.familyContact,
        label: 'Direktkontakt',
        description: 'Eltern und Trainerteam kurz abstimmen',
        icon: Icons.forum_rounded,
      ),
      if (widget.staffView)
        const _CommunicationDestination(
          view: _CommunicationView.pitchRequests,
          label: 'Platzanfragen',
          description: 'Überschneidungen und Jugendvorrang klären',
          icon: Icons.stadium_rounded,
        ),
      const _CommunicationDestination(
        view: _CommunicationView.notifications,
        label: 'Benachrichtigungen',
        description: 'Persönliche Hinweise im Blick behalten',
        icon: Icons.notifications_rounded,
      ),
      const _CommunicationDestination(
        view: _CommunicationView.settings,
        label: 'Einstellungen',
        description: 'Push-Nachrichten und Geräte verwalten',
        icon: Icons.tune_rounded,
      ),
    ];
    final selectedIndex = destinations.indexWhere(
      (destination) => destination.view == _view,
    );
    final effectiveView =
        selectedIndex < 0 ? _CommunicationView.announcements : _view;
    return PageScaffold(
      title: 'Mitteilungscenter',
      subtitle:
          'Alle Informationen, Abstimmungen und Benachrichtigungen zentral organisiert.',
      denseMobileHeader: true,
      action:
          widget.staffView && effectiveView == _CommunicationView.announcements
              ? FilledButton.icon(
                  onPressed: _compose,
                  icon: const Icon(Icons.add_comment_rounded),
                  label: const Text('Neue Mitteilung'),
                )
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommunicationNavigation(
            destinations: destinations,
            selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
            onSelected: (value) =>
                setState(() => _view = destinations[value].view),
          ),
          SizedBox(height: MediaQuery.sizeOf(context).width < 720 ? 10 : 24),
          if (effectiveView == _CommunicationView.announcements)
            _AnnouncementList(
              key: ValueKey('announcements-$_revision'),
              staffView: widget.staffView,
              onChanged: _reload,
            )
          else if (effectiveView == _CommunicationView.familyContact)
            _FamilyContactPanel(staffView: widget.staffView)
          else if (effectiveView == _CommunicationView.pitchRequests)
            _PitchConflictRequestList(
              key: ValueKey('pitch-conflicts-$_revision'),
              onChanged: _reload,
            )
          else if (effectiveView == _CommunicationView.notifications)
            _NotificationList(
              key: ValueKey('notifications-$_revision'),
              canDelete: widget.staffView,
              onChanged: _reload,
            )
          else
            _NotificationSettings(key: ValueKey('settings-$_revision')),
        ],
      ),
    );
  }

  Future<void> _compose() async {
    final organization = await ref.read(organizationProvider.future);
    if (!mounted) return;
    final draft = await showDialog<_AnnouncementDraft>(
      context: context,
      builder: (context) => _ComposeAnnouncementDialog(
        organization: organization,
      ),
    );
    if (draft == null) return;
    try {
      await ref.read(repositoryProvider).saveAnnouncement(
            title: draft.title,
            body: draft.body,
            teamIds: draft.teamIds,
            audience: draft.audience,
            priority: draft.priority,
            status: draft.status,
            publishAt: draft.publishAt,
            requireReadReceipt: draft.requireReadReceipt,
            pushEnabled: draft.pushEnabled,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            draft.status == AnnouncementStatus.draft
                ? 'Entwurf gespeichert.'
                : draft.status == AnnouncementStatus.scheduled
                    ? 'Mitteilung wurde eingeplant.'
                    : 'Mitteilung wurde veröffentlicht.',
          ),
        ),
      );
      _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Mitteilung konnte nicht gespeichert werden.')),
      );
    }
  }
}

enum _CommunicationView {
  announcements,
  familyContact,
  pitchRequests,
  notifications,
  settings,
}

class _FamilyContactPanel extends ConsumerStatefulWidget {
  const _FamilyContactPanel({required this.staffView});

  final bool staffView;

  @override
  ConsumerState<_FamilyContactPanel> createState() =>
      _FamilyContactPanelState();
}

class _FamilyContactPanelState extends ConsumerState<_FamilyContactPanel> {
  FamilyContactInbox? _inbox;
  Object? _error;
  bool _loading = true;
  bool _sending = false;
  String? _activeConversationId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final inbox = await ref.read(repositoryProvider).familyContacts();
      if (!mounted) return;
      setState(() {
        _inbox = inbox;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _inbox == null) {
      return const LogoLoadingPanel(
        message: 'Direktkontakte werden geladen …',
      );
    }
    if (_error != null && _inbox == null) {
      return EmptyState(
        icon: Icons.forum_outlined,
        title: 'Direktkontakt nicht erreichbar',
        message: 'Die kurzen Nachrichten konnten gerade nicht geladen werden.',
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Erneut laden'),
        ),
      );
    }
    final inbox = _inbox!;
    final grouped = <String, List<FamilyContactMessage>>{};
    for (final message in inbox.messages) {
      grouped.putIfAbsent(message.conversationId, () => []).add(message);
    }
    final conversations = grouped.values.toList()
      ..sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));
    final canStartConversation = widget.staffView
        ? inbox.contactOptions.isNotEmpty
        : inbox.teamOptions.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.teal.withValues(alpha: .08),
            border: Border.all(
              color: AppColors.teal.withValues(alpha: .22),
            ),
            borderRadius: BorderRadius.circular(17),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final info = Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.lock_clock_rounded,
                      color: AppColors.teal,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.staffView
                              ? compact
                                  ? 'Eltern kontaktieren'
                                  : 'Direkter Draht zu den Eltern'
                              : compact
                                  ? 'Trainerteam schreiben'
                                  : 'Kurzer Draht zum Trainerteam',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Nachrichten, Medien und Sicherungen · vollständige automatische Löschung nach ${inbox.retentionDays} Tagen',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final compose = FilledButton.icon(
                onPressed: _sending || !canStartConversation
                    ? null
                    : () => _compose(inbox: inbox),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text(
                  widget.staffView
                      ? 'Eltern kontaktieren'
                      : 'Trainerteam schreiben',
                ),
              );
              if (compact) {
                return Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _sending || !canStartConversation
                            ? null
                            : () => _compose(inbox: inbox),
                        child: info,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Tooltip(
                      message: widget.staffView
                          ? 'Eltern kontaktieren'
                          : 'Trainerteam schreiben',
                      child: IconButton.filled(
                        onPressed: _sending || !canStartConversation
                            ? null
                            : () => _compose(inbox: inbox),
                        icon: const Icon(Icons.edit_rounded, size: 19),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 12),
                  compose,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(minHeight: 3),
        if (conversations.isEmpty)
          EmptyState(
            icon: Icons.mark_chat_unread_outlined,
            title: widget.staffView
                ? 'Noch kein Direktkontakt'
                : 'Noch kein Direktkontakt',
            message: widget.staffView
                ? 'Hier kannst du Eltern deiner ausgewählten Mannschaft direkt anschreiben.'
                : 'Hier kannst du eine kurze organisatorische Frage direkt an das zuständige Trainerteam senden.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final selectedId = _activeConversationId ??
                  conversations.first.first.conversationId;
              final selected = conversations.firstWhere(
                (messages) => messages.first.conversationId == selectedId,
                orElse: () => conversations.first,
              );
              final conversationList = _FamilyConversationList(
                conversations: conversations,
                staffView: widget.staffView,
                selectedConversationId: selected.first.conversationId,
                onOpen: (messages) {
                  if (constraints.maxWidth < 720) {
                    _openThread(messages);
                    return;
                  }
                  setState(() =>
                      _activeConversationId = messages.first.conversationId);
                },
                onReply: (messages) => _compose(
                  inbox: inbox,
                  messages: messages,
                ),
              );
              if (constraints.maxWidth < 720) return conversationList;
              final availableHeight = MediaQuery.sizeOf(context).height - 250;
              return SizedBox(
                height: availableHeight.clamp(520.0, 760.0),
                child: AdaptiveTwoPane(
                  minimumTwoPaneWidth: 720,
                  primaryWidth: 318,
                  primary: conversationList,
                  secondary: _FamilyContactThreadPane(
                    messages: selected,
                    staffView: widget.staffView,
                    retentionDays: inbox.retentionDays,
                    sending: _sending,
                    onSend: (draft) => _sendReply(
                      selected,
                      draft,
                    ),
                  ),
                  compact: conversationList,
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _sendReply(
    List<FamilyContactMessage> messages,
    _FamilyContactReplyDraft draft,
  ) async {
    if (_sending || !mounted) return;
    setState(() => _sending = true);
    try {
      await ref.read(repositoryProvider).sendFamilyContact(
            message: draft.message,
            teamId: messages.first.teamId,
            conversationId: messages.first.conversationId,
            attachmentBytes: draft.attachmentBytes,
            attachmentName: draft.attachmentName,
            attachmentMimeType: draft.attachmentMimeType,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nachricht wurde sicher gesendet.')),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Die Nachricht konnte nicht gesendet werden. Bitte Verbindung prüfen und erneut versuchen.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openThread(List<FamilyContactMessage> messages) async {
    final replyController = TextEditingController();
    var replyText = '';
    PlatformFile? replyAttachment;
    final reply = await showModalBottomSheet<_FamilyContactReplyDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appColors.canvas,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: .9,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                decoration: BoxDecoration(
                  color: context.appColors.surface,
                  border: Border(
                    bottom: BorderSide(color: context.appColors.outline),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: context.appColors.brandSoft,
                      child: const Icon(
                        Icons.forum_rounded,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.staffView
                                ? _parentConversationTitle(messages)
                                : 'Trainerteam · ${messages.first.teamName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Vollständige Löschung inkl. Sicherungen nach ${_inbox?.retentionDays ?? 30} Tagen',
                            style: const TextStyle(
                              color: AppColors.teal,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Unterhaltung schließen',
                      onPressed: () => Navigator.pop(sheetContext),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 5),
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, reverseIndex) {
                    final index = messages.length - reverseIndex - 1;
                    return _FamilyContactBubble(message: messages[index]);
                  },
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(10, 3, 10, 5),
                child: Row(
                  children: [
                    for (final suggestion in const [
                      'Danke für die Info!',
                      'Alles klar 👍',
                      'Ich melde mich später.',
                    ]) ...[
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.bolt_rounded, size: 15),
                        label: Text(suggestion),
                        onPressed: () {
                          replyController.text = suggestion;
                          replyController.selection = TextSelection.collapsed(
                            offset: suggestion.length,
                          );
                          setSheetState(() => replyText = suggestion);
                        },
                      ),
                      const SizedBox(width: 5),
                    ],
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  10,
                  7,
                  8,
                  8 + MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                decoration: BoxDecoration(
                  color: context.appColors.surface,
                  border: Border(
                    top: BorderSide(color: context.appColors.outline),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (replyAttachment != null)
                      _PendingMessengerAttachment(
                        file: replyAttachment!,
                        onRemove: () =>
                            setSheetState(() => replyAttachment = null),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Bild, Video, Audio oder PDF anhängen',
                          onPressed: () async {
                            final file = await _pickFamilyContactFile();
                            if (file != null) {
                              setSheetState(() => replyAttachment = file);
                            }
                          },
                          icon: const Icon(Icons.add_circle_outline_rounded),
                        ),
                        Expanded(
                          child: TextField(
                            controller: replyController,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (value) =>
                                setSheetState(() => replyText = value),
                            decoration: const InputDecoration(
                              hintText: 'Nachricht schreiben …',
                              counterText: '',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          tooltip: 'Nachricht senden',
                          onPressed: replyText.trim().isEmpty &&
                                  replyAttachment == null
                              ? null
                              : () => Navigator.pop(
                                    sheetContext,
                                    _FamilyContactReplyDraft.fromFile(
                                      message: replyText.trim(),
                                      file: replyAttachment,
                                    ),
                                  ),
                          icon: const Icon(Icons.send_rounded, size: 19),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 48),
                      child: Text(
                        'Alles wird inkl. Sicherungen nach 30 Tagen vollständig gelöscht.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    replyController.dispose();
    if (reply == null || !mounted) return;
    await _sendReply(messages, reply);
  }

  Future<void> _compose({
    required FamilyContactInbox inbox,
    List<FamilyContactMessage>? messages,
  }) async {
    var messageText = '';
    PlatformFile? selectedAttachment;
    var selectedTeamId = messages?.first.teamId ??
        (inbox.teamOptions.length == 1 ? inbox.teamOptions.first.id : null);
    var selectedParentId = messages?.first.parentId;
    if (messages == null && widget.staffView && selectedTeamId != null) {
      final contacts = inbox.contactOptions
          .where((contact) => contact.teamId == selectedTeamId)
          .toList();
      if (contacts.length == 1) selectedParentId = contacts.first.id;
    }
    final draft = await showModalBottomSheet<_FamilyContactDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            14 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    messages == null
                        ? (widget.staffView
                            ? 'Eltern kontaktieren'
                            : 'Trainerteam schreiben')
                        : 'Antworten',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Bitte nur kurze organisatorische Absprachen senden. Für Notfälle den bekannten direkten Kontakt nutzen.',
                  ),
                  const SizedBox(height: 12),
                  if (messages == null && inbox.teamOptions.length > 1)
                    DropdownButtonFormField<String>(
                      initialValue: selectedTeamId,
                      decoration: const InputDecoration(
                        labelText: 'Mannschaft',
                        prefixIcon: Icon(Icons.groups_rounded),
                      ),
                      items: [
                        for (final team in inbox.teamOptions)
                          DropdownMenuItem(
                            value: team.id,
                            child: Text(team.name),
                          ),
                      ],
                      onChanged: (value) => setSheetState(() {
                        selectedTeamId = value;
                        selectedParentId = null;
                        final contacts = inbox.contactOptions
                            .where((contact) => contact.teamId == value)
                            .toList();
                        if (contacts.length == 1) {
                          selectedParentId = contacts.first.id;
                        }
                      }),
                    )
                  else
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.groups_rounded),
                      title: Text(
                        messages?.first.teamName ??
                            inbox.teamOptions.firstOrNull?.name ??
                            'Mannschaft',
                      ),
                      subtitle: Text(
                        widget.staffView
                            ? 'Mannschaft für den Elternkontakt'
                            : 'Empfänger: zuständiges Trainerteam',
                      ),
                    ),
                  if (messages == null && widget.staffView) ...[
                    const SizedBox(height: 10),
                    Builder(
                      builder: (context) {
                        final contacts = inbox.contactOptions
                            .where(
                              (contact) => contact.teamId == selectedTeamId,
                            )
                            .toList();
                        final initialParentId = contacts.any(
                          (contact) => contact.id == selectedParentId,
                        )
                            ? selectedParentId
                            : null;
                        return DropdownButtonFormField<String>(
                          key: ValueKey('family-contact-$selectedTeamId'),
                          initialValue: initialParentId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Elternkontakt',
                            prefixIcon: Icon(Icons.family_restroom_rounded),
                          ),
                          items: [
                            for (final contact in contacts)
                              DropdownMenuItem(
                                value: contact.id,
                                child: Text(
                                  contact.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setSheetState(() => selectedParentId = value),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextFormField(
                    autofocus: true,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (value) => messageText = value,
                    decoration: const InputDecoration(
                      labelText: 'Nachricht',
                      hintText: 'Worum geht es?',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (selectedAttachment != null)
                    _PendingMessengerAttachment(
                      file: selectedAttachment!,
                      onRemove: () =>
                          setSheetState(() => selectedAttachment = null),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final file = await _pickFamilyContactFile();
                      if (file != null) {
                        setSheetState(() => selectedAttachment = file);
                      }
                    },
                    icon: const Icon(Icons.attach_file_rounded),
                    label: Text(
                      selectedAttachment == null
                          ? 'Bild, Video, Audio oder PDF anhängen'
                          : 'Anderen Anhang auswählen',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Nachricht und Anhang werden am selben Tag nach 30 Tagen vollständig gelöscht.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () {
                      final text = messageText.trim();
                      if ((text.isEmpty && selectedAttachment == null) ||
                          selectedTeamId == null ||
                          (widget.staffView &&
                              messages == null &&
                              selectedParentId == null)) {
                        return;
                      }
                      Navigator.pop(
                        sheetContext,
                        _FamilyContactDraft(
                          message: text,
                          teamId: selectedTeamId!,
                          conversationId: messages?.first.conversationId,
                          parentId: messages == null ? selectedParentId : null,
                          attachmentBytes: selectedAttachment?.bytes,
                          attachmentName: selectedAttachment?.name,
                          attachmentMimeType: selectedAttachment == null
                              ? null
                              : _familyContactMimeType(selectedAttachment!),
                        ),
                      );
                    },
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Sicher senden'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await ref.read(repositoryProvider).sendFamilyContact(
            message: draft.message,
            teamId: draft.teamId,
            conversationId: draft.conversationId,
            parentId: draft.parentId,
            attachmentBytes: draft.attachmentBytes,
            attachmentName: draft.attachmentName,
            attachmentMimeType: draft.attachmentMimeType,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nachricht wurde sicher gesendet.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Die Nachricht konnte nicht gesendet werden. Bitte Verbindung prüfen und erneut versuchen.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _FamilyContactReplyDraft {
  const _FamilyContactReplyDraft({
    required this.message,
    this.attachmentBytes,
    this.attachmentName,
    this.attachmentMimeType,
  });

  factory _FamilyContactReplyDraft.fromFile({
    required String message,
    PlatformFile? file,
  }) =>
      _FamilyContactReplyDraft(
        message: message,
        attachmentBytes: file?.bytes,
        attachmentName: file?.name,
        attachmentMimeType: file == null ? null : _familyContactMimeType(file),
      );

  final String message;
  final Uint8List? attachmentBytes;
  final String? attachmentName;
  final String? attachmentMimeType;
}

class _FamilyConversationList extends StatelessWidget {
  const _FamilyConversationList({
    required this.conversations,
    required this.staffView,
    required this.selectedConversationId,
    required this.onOpen,
    required this.onReply,
  });

  final List<List<FamilyContactMessage>> conversations;
  final bool staffView;
  final String selectedConversationId;
  final ValueChanged<List<FamilyContactMessage>> onOpen;
  final ValueChanged<List<FamilyContactMessage>> onReply;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final cards = <Widget>[
            for (final messages in conversations)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border:
                        messages.first.conversationId == selectedConversationId
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              )
                            : null,
                  ),
                  child: _FamilyContactThreadCard(
                    messages: messages,
                    staffView: staffView,
                    onOpen: () => onOpen(messages),
                    onReply: () => onReply(messages),
                  ),
                ),
              ),
          ];
          final header = Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Unterhaltungen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${conversations.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          );
          if (!constraints.hasBoundedHeight) {
            return Column(children: [header, ...cards]);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: cards,
                ),
              ),
            ],
          );
        },
      );
}

class _FamilyContactThreadPane extends StatelessWidget {
  const _FamilyContactThreadPane({
    required this.messages,
    required this.staffView,
    required this.retentionDays,
    required this.sending,
    required this.onSend,
  });

  final List<FamilyContactMessage> messages;
  final bool staffView;
  final int retentionDays;
  final bool sending;
  final Future<void> Function(_FamilyContactReplyDraft draft) onSend;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 9),
              color: context.appColors.surfaceRaised,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: context.appColors.brandSoft,
                    child: const Icon(Icons.forum_rounded, size: 19),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          staffView
                              ? _parentConversationTitle(messages)
                              : 'Trainerteam · ${messages.first.teamName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Automatische vollständige Löschung inkl. Sicherungen nach $retentionDays Tagen',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.teal,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const Tooltip(
                    message:
                        'Texte, Bilder, Videos, Audiodateien und Dokumente werden vollständig gelöscht.',
                    child: Icon(Icons.verified_user_outlined, size: 20),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.appColors.outline),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (context, reverseIndex) {
                  final index = messages.length - reverseIndex - 1;
                  return _FamilyContactBubble(message: messages[index]);
                },
              ),
            ),
            _FamilyContactComposer(
              sending: sending,
              onSend: onSend,
            ),
          ],
        ),
      );
}

class _FamilyContactComposer extends StatefulWidget {
  const _FamilyContactComposer({required this.sending, required this.onSend});

  final bool sending;
  final Future<void> Function(_FamilyContactReplyDraft draft) onSend;

  @override
  State<_FamilyContactComposer> createState() => _FamilyContactComposerState();
}

class _FamilyContactComposerState extends State<_FamilyContactComposer> {
  final _controller = TextEditingController();
  PlatformFile? _attachment;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (widget.sending || (message.isEmpty && _attachment == null)) return;
    final draft = _FamilyContactReplyDraft.fromFile(
      message: message,
      file: _attachment,
    );
    await widget.onSend(draft);
    if (!mounted) return;
    _controller.clear();
    setState(() => _attachment = null);
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 9),
        decoration: BoxDecoration(
          color: context.appColors.surfaceRaised,
          border: Border(top: BorderSide(color: context.appColors.outline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final suggestion in const [
                    'Danke für die Info!',
                    'Alles klar 👍',
                    'Ich melde mich später.',
                  ]) ...[
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(suggestion),
                      onPressed: widget.sending
                          ? null
                          : () {
                              _controller.text = suggestion;
                              _controller.selection = TextSelection.collapsed(
                                offset: suggestion.length,
                              );
                              setState(() {});
                            },
                    ),
                    const SizedBox(width: 5),
                  ],
                ],
              ),
            ),
            if (_attachment != null)
              _PendingMessengerAttachment(
                file: _attachment!,
                onRemove: () => setState(() => _attachment = null),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Bild, Video, Audio oder PDF anhängen',
                  onPressed: widget.sending
                      ? null
                      : () async {
                          final file = await _pickFamilyContactFile();
                          if (mounted && file != null) {
                            setState(() => _attachment = file);
                          }
                        },
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Nachricht schreiben …',
                      counterText: '',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Sicher senden',
                  onPressed: widget.sending ||
                          (_controller.text.trim().isEmpty &&
                              _attachment == null)
                      ? null
                      : _send,
                  icon: widget.sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 19),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 48),
              child: Text(
                'Nachrichten, Medien und Sicherungen werden nach 30 Tagen vollständig gelöscht.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                    ),
              ),
            ),
          ],
        ),
      );
}

class _PendingMessengerAttachment extends StatelessWidget {
  const _PendingMessengerAttachment(
      {required this.file, required this.onRemove});

  final PlatformFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(9, 6, 4, 6),
        decoration: BoxDecoration(
          color: context.appColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.appColors.outline),
        ),
        child: Row(
          children: [
            Icon(_familyContactFileIcon(_familyContactMimeType(file)),
                size: 19),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${file.name} · ${_fileSizeLabel(file.size)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Anhang entfernen',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      );
}

Future<PlatformFile?> _pickFamilyContactFile() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const [
      'jpg',
      'jpeg',
      'png',
      'webp',
      'mp4',
      'webm',
      'mp3',
      'm4a',
      'aac',
      'ogg',
      'pdf',
    ],
    withData: true,
    allowMultiple: false,
  );
  final file = result?.files.firstOrNull;
  return file?.bytes == null ? null : file;
}

String _familyContactMimeType(PlatformFile file) =>
    switch (file.extension?.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'mp4' => 'video/mp4',
      'webm' => 'video/webm',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'ogg' => 'audio/ogg',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };

IconData _familyContactFileIcon(String contentType) {
  if (contentType.startsWith('image/')) return Icons.image_rounded;
  if (contentType.startsWith('video/')) return Icons.videocam_rounded;
  if (contentType.startsWith('audio/')) return Icons.graphic_eq_rounded;
  return Icons.picture_as_pdf_rounded;
}

String _fileSizeLabel(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}

class _FamilyContactDraft {
  const _FamilyContactDraft({
    required this.message,
    required this.teamId,
    this.conversationId,
    this.parentId,
    this.attachmentBytes,
    this.attachmentName,
    this.attachmentMimeType,
  });

  final String message;
  final String teamId;
  final String? conversationId;
  final String? parentId;
  final Uint8List? attachmentBytes;
  final String? attachmentName;
  final String? attachmentMimeType;
}

class _FamilyContactThreadCard extends StatelessWidget {
  const _FamilyContactThreadCard({
    required this.messages,
    required this.staffView,
    required this.onOpen,
    required this.onReply,
  });

  final List<FamilyContactMessage> messages;
  final bool staffView;
  final VoidCallback onOpen;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final last = messages.last;
    return Card(
      key: ValueKey('family-contact-thread-${last.conversationId}'),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 8, 5, 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.appColors.brandSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staffView
                          ? _parentConversationTitle(messages)
                          : 'Trainerteam · ${last.teamName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      last.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${messages.length} ${messages.length == 1 ? 'Nachricht' : 'Nachrichten'} · ${_contactTimestamp(last.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onReply,
                tooltip: 'Antworten',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                icon: const Icon(Icons.reply_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FamilyContactBubble extends StatelessWidget {
  const _FamilyContactBubble({required this.message});

  final FamilyContactMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final maximum =
        (MediaQuery.sizeOf(context).width * .78).clamp(220.0, 520.0).toDouble();
    return Align(
      alignment:
          message.sentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        button: true,
        hint: 'Lange drücken, um die Nachricht zu kopieren',
        child: InkWell(
          key: ValueKey('family-contact-message-${message.id}'),
          borderRadius: BorderRadius.circular(16),
          onLongPress: () async {
            await Clipboard.setData(ClipboardData(text: message.message));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Nachricht kopiert.')),
            );
          },
          child: Container(
            constraints: BoxConstraints(
              maxWidth: maximum,
            ),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: message.sentByMe ? colors.brandSoft : colors.surfaceRaised,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(message.sentByMe ? 16 : 4),
                bottomRight: Radius.circular(message.sentByMe ? 4 : 16),
              ),
              border: Border.all(color: colors.outline),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!message.sentByMe)
                  Text(
                    message.senderName,
                    style: const TextStyle(
                      color: AppColors.teal,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                if (message.message.isNotEmpty &&
                    !(message.attachment != null &&
                        message.message == '📎 ${message.attachment!.name}'))
                  Text(message.message),
                if (message.attachment != null) ...[
                  if (message.message.isNotEmpty) const SizedBox(height: 6),
                  _FamilyContactAttachmentView(
                    attachment: message.attachment!,
                  ),
                ],
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _contactTime(message.createdAt),
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                    if (message.sentByMe) ...[
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.done_all_rounded,
                        size: 13,
                        color: AppColors.teal,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Löschung: ${_contactDeletionDate(message.expiresAt)}',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FamilyContactAttachmentView extends StatelessWidget {
  const _FamilyContactAttachmentView({required this.attachment});

  final FamilyContactAttachment attachment;

  Future<void> _open() async {
    final uri = Uri.tryParse(attachment.downloadUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = Row(
      children: [
        Icon(_familyContactFileIcon(attachment.contentType), size: 18),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            attachment.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          _fileSizeLabel(attachment.sizeBytes),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 9),
        ),
        const SizedBox(width: 3),
        const Icon(Icons.open_in_new_rounded, size: 15),
      ],
    );
    return Material(
      color: context.appColors.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (attachment.isImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.network(
                    attachment.downloadUrl,
                    height: 128,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 72,
                      alignment: Alignment.center,
                      color: context.appColors.surface,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              if (attachment.isImage) const SizedBox(height: 7),
              label,
            ],
          ),
        ),
      ),
    );
  }
}

String _parentConversationTitle(List<FamilyContactMessage> messages) {
  final parentName = messages.first.parentName;
  return '$parentName · ${messages.first.teamName}';
}

String _contactTimestamp(DateTime value) {
  final local = value.toLocal();
  return '${local.day}.${local.month}.${local.year} · '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')} Uhr';
}

String _contactTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _contactDeletionDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.${local.year}, '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')} Uhr';
}

class _CommunicationDestination {
  const _CommunicationDestination({
    required this.view,
    required this.label,
    required this.description,
    required this.icon,
  });

  final _CommunicationView view;
  final String label;
  final String description;
  final IconData icon;
}

class _CommunicationNavigation extends StatelessWidget {
  const _CommunicationNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_CommunicationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        if (compact) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < destinations.length; index++) ...[
                  ChoiceChip(
                    avatar: Icon(destinations[index].icon, size: 18),
                    label: Text(destinations[index].label),
                    selected: selectedIndex == index,
                    onSelected: (_) => onSelected(index),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 3),
                  ),
                  if (index != destinations.length - 1)
                    const SizedBox(width: 5),
                ],
              ],
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.appColors.outline),
            boxShadow: [
              BoxShadow(
                color: context.appColors.shadow,
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var index = 0; index < destinations.length; index++)
                Expanded(
                  child: _CommunicationNavigationItem(
                    destination: destinations[index],
                    selected: selectedIndex == index,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CommunicationNavigationItem extends StatelessWidget {
  const _CommunicationNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _CommunicationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.yellow.withValues(alpha: .2)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? AppColors.yellow : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(destination.icon, size: 21, color: AppColors.navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      destination.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.muted,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PitchConflictRequestList extends ConsumerWidget {
  const _PitchConflictRequestList({
    super.key,
    required this.onChanged,
  });

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<PitchConflictRequestModel>>(
      future: ref.read(repositoryProvider).pitchConflictRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: LogoLoadingPanel(message: 'Nachrichten werden geladen …'),
          );
        }
        if (snapshot.hasError) return _ErrorCard(onRetry: onChanged);
        final items = snapshot.data ?? const [];
        final isSystemAdmin =
            ref.read(authProvider).user?.role == UserRole.superAdmin;
        final priorityInfo = Card(
          color: AppColors.teal.withValues(alpha: .08),
          child: ListTile(
            leading: const Icon(Icons.shield_rounded, color: AppColors.teal),
            title: const Text('Jugendmannschaften haben immer Vorrang'),
            subtitle: const Text(
              'Bei einer Überschneidung mit Freizeitkickern entsteht keine '
              'Freigabeanfrage. Die Freizeitkicker und die Systemadministration '
              'erhalten automatisch nur eine Belegungsinformation.',
            ),
            trailing: isSystemAdmin
                ? IconButton(
                    tooltip: 'Freizeit-Belegung verwalten',
                    onPressed: () => context.go('/trainer/training'),
                    icon: const Icon(Icons.edit_calendar_rounded),
                  )
                : null,
          ),
        );
        if (items.isEmpty) {
          return Column(
            children: [
              priorityInfo,
              const SizedBox(height: 12),
              const EmptyState(
                icon: Icons.event_available_rounded,
                title: 'Keine offenen Platzabstimmungen',
                message:
                    'Anfragen wegen Überschneidungen mit Trainings erscheinen hier.',
              ),
            ],
          );
        }
        return Column(
          children: [
            priorityInfo,
            const SizedBox(height: 12),
            for (final item in items) ...[
              _PitchConflictRequestCard(
                request: item,
                onRespond: item.canRespond
                    ? (status) => _respond(context, ref, item, status)
                    : null,
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    PitchConflictRequestModel request,
    PitchConflictRequestStatus status,
  ) async {
    final controller = TextEditingController();
    final label = switch (status) {
      PitchConflictRequestStatus.approved => 'Freigeben',
      PitchConflictRequestStatus.declined => 'Ablehnen',
      PitchConflictRequestStatus.callbackRequested => 'Rückruf anfordern',
      _ => 'Bestätigen',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.eventTitle} auf ${request.pitch}\n'
              'Konflikt: ${request.trainingScheduleValue}',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Antwort (optional)',
                hintText: 'Hinweis zur Abstimmung',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      controller.dispose();
      return;
    }
    try {
      await ref.read(repositoryProvider).respondToPitchConflictRequest(
            requestId: request.id,
            status: status,
            responseMessage:
                controller.text.trim().isEmpty ? null : controller.text.trim(),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Platzanfrage: $label wurde übermittelt.')),
      );
      onChanged();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Antwort konnte nicht übermittelt werden.'),
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}

class _PitchConflictRequestCard extends StatelessWidget {
  const _PitchConflictRequestCard({
    required this.request,
    required this.onRespond,
  });

  final PitchConflictRequestModel request;
  final ValueChanged<PitchConflictRequestStatus>? onRespond;

  @override
  Widget build(BuildContext context) {
    final incoming = request.direction == 'INCOMING';
    final color = switch (request.status) {
      PitchConflictRequestStatus.pending => AppColors.orange,
      PitchConflictRequestStatus.approved => Colors.green,
      PitchConflictRequestStatus.declined =>
        Theme.of(context).colorScheme.error,
      PitchConflictRequestStatus.callbackRequested => AppColors.blue,
      PitchConflictRequestStatus.cancelled => AppColors.muted,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .12),
                  child: Icon(Icons.stadium_rounded, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            request.eventTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Chip(
                            label: Text(_pitchRequestStatus(request.status)),
                            side: BorderSide(color: color),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_dateTime(request.eventStartAt)} · ${request.pitch}',
                      ),
                      Text(
                        'Betroffen: ${request.trainingTeamName} · '
                        '${request.trainingScheduleValue}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              incoming
                  ? 'Anfrage von ${request.requesterName}'
                  : 'Anfrage an ${request.recipientName}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (request.message?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(request.message!),
            ],
            if (request.responseMessage?.isNotEmpty == true) ...[
              const Divider(height: 24),
              Text('Antwort: ${request.responseMessage!}'),
            ],
            if (request.status ==
                    PitchConflictRequestStatus.callbackRequested &&
                request.recipientPhone?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri(scheme: 'tel', path: request.recipientPhone),
                ),
                icon: const Icon(Icons.phone_rounded),
                label: Text('${request.recipientName} zurückrufen'),
              ),
            ],
            if (onRespond != null) ...[
              const Divider(height: 28),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () =>
                        onRespond!(PitchConflictRequestStatus.approved),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Freigeben'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        onRespond!(PitchConflictRequestStatus.declined),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Ablehnen'),
                  ),
                  OutlinedButton.icon(
                    onPressed: request.recipientPhone?.isNotEmpty == true
                        ? () => onRespond!(
                              PitchConflictRequestStatus.callbackRequested,
                            )
                        : null,
                    icon: const Icon(Icons.phone_callback_rounded),
                    label: Text(
                      request.recipientPhone?.isNotEmpty == true
                          ? 'Bitte um Rückruf'
                          : 'Keine Telefonnummer hinterlegt',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnnouncementList extends ConsumerStatefulWidget {
  const _AnnouncementList({
    super.key,
    required this.staffView,
    required this.onChanged,
  });

  final bool staffView;
  final VoidCallback onChanged;

  @override
  ConsumerState<_AnnouncementList> createState() => _AnnouncementListState();
}

class _AnnouncementListState extends ConsumerState<_AnnouncementList> {
  final _searchController = TextEditingController();
  String _query = '';
  AnnouncementStatus? _statusFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = ref.watch(authProvider).user?.role == UserRole.superAdmin;
    return FutureBuilder<List<AnnouncementModel>>(
      future: ref
          .read(repositoryProvider)
          .announcements(includeDrafts: widget.staffView),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: LogoLoadingPanel(message: 'Mitteilungen werden geladen …'),
          );
        }
        if (snapshot.hasError) {
          return _ErrorCard(onRetry: widget.onChanged);
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.forum_outlined,
            title: 'Noch keine Mitteilungen',
            message: 'Neue Team-Nachrichten erscheinen automatisch hier.',
          );
        }
        final normalizedQuery = _query.trim().toLowerCase();
        final filtered = items.where((item) {
          final matchesText = normalizedQuery.isEmpty ||
              item.title.toLowerCase().contains(normalizedQuery) ||
              item.body.toLowerCase().contains(normalizedQuery) ||
              item.teamNames.any(
                (name) => name.toLowerCase().contains(normalizedQuery),
              );
          return matchesText &&
              (_statusFilter == null || item.status == _statusFilter);
        }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AnnouncementToolbar(
              itemCount: items.length,
              staffView: widget.staffView,
              searchController: _searchController,
              statusFilter: _statusFilter,
              onSearchChanged: (value) => setState(() => _query = value),
              onStatusChanged: (value) => setState(() => _statusFilter = value),
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Keine passenden Mitteilungen',
                message: 'Passe die Suche oder den Statusfilter an.',
                action: TextButton.icon(
                  onPressed: () => setState(() {
                    _searchController.clear();
                    _query = '';
                    _statusFilter = null;
                  }),
                  icon: const Icon(Icons.filter_alt_off_rounded),
                  label: const Text('Filter zurücksetzen'),
                ),
              )
            else
              for (final item in filtered) ...[
                _AnnouncementCard(
                  announcement: item,
                  staffView: widget.staffView,
                  deletePermanently: canDelete,
                  onDelete: widget.staffView
                      ? () => _delete(
                            context,
                            ref,
                            item,
                            permanently: canDelete,
                          )
                      : null,
                  onOpened: () async {
                    if (!item.isRead &&
                        item.status == AnnouncementStatus.published) {
                      await ref
                          .read(repositoryProvider)
                          .markAnnouncementRead(item.id);
                      widget.onChanged();
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AnnouncementModel announcement, {
    required bool permanently,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text(permanently
            ? 'Mitteilung endgültig löschen?'
            : 'Mitteilung löschen?'),
        content: Text(
          permanently
              ? '„${announcement.title}“ wird für alle Empfänger endgültig gelöscht. Auch Benachrichtigungen und Lesebestätigungen werden entfernt.'
              : '„${announcement.title}“ wird für alle Empfänger ausgeblendet und nicht mehr versendet. Die Löschung bleibt für die Systemadministration nachvollziehbar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: Icon(permanently
                ? Icons.delete_forever_rounded
                : Icons.delete_outline_rounded),
            label: Text(permanently ? 'Endgültig löschen' : 'Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      if (permanently) {
        await ref
            .read(repositoryProvider)
            .deleteAnnouncementPermanently(announcement.id);
      } else {
        await ref.read(repositoryProvider).deleteAnnouncement(announcement.id);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(permanently
              ? 'Mitteilung wurde endgültig gelöscht.'
              : 'Mitteilung wurde gelöscht.'),
        ),
      );
      widget.onChanged();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mitteilung konnte nicht gelöscht werden.'),
        ),
      );
    }
  }
}

class _AnnouncementToolbar extends StatelessWidget {
  const _AnnouncementToolbar({
    required this.itemCount,
    required this.staffView,
    required this.searchController,
    required this.statusFilter,
    required this.onSearchChanged,
    required this.onStatusChanged,
  });

  final int itemCount;
  final bool staffView;
  final TextEditingController searchController;
  final AnnouncementStatus? statusFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<AnnouncementStatus?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appColors.outline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final search = TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Mitteilungen durchsuchen',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          );
          final status = DropdownButtonFormField<AnnouncementStatus?>(
            key: ValueKey(statusFilter),
            initialValue: statusFilter,
            decoration: InputDecoration(
              labelText: compact ? null : 'Status',
              prefixIcon:
                  compact ? null : const Icon(Icons.filter_list_rounded),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<AnnouncementStatus?>(
                value: null,
                child: Text('Alle Status'),
              ),
              ...AnnouncementStatus.values.map(
                (value) => DropdownMenuItem<AnnouncementStatus?>(
                  value: value,
                  child: Text(_status(value)),
                ),
              ),
            ],
            onChanged: onStatusChanged,
          );
          final count = Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: context.appColors.surfaceMuted,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$itemCount ${itemCount == 1 ? 'Mitteilung' : 'Mitteilungen'}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: search),
                    if (staffView) ...[
                      const SizedBox(width: 6),
                      SizedBox(width: 122, child: status),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Align(alignment: Alignment.centerRight, child: count),
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 3, child: search),
              if (staffView) ...[
                const SizedBox(width: 12),
                SizedBox(width: 220, child: status),
              ],
              const SizedBox(width: 12),
              count,
            ],
          );
        },
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.staffView,
    required this.onOpened,
    this.deletePermanently = false,
    this.onDelete,
  });

  final AnnouncementModel announcement;
  final bool staffView;
  final Future<void> Function() onOpened;
  final Future<void> Function()? onDelete;
  final bool deletePermanently;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final color = switch (announcement.priority) {
      AnnouncementPriority.urgent => Colors.redAccent,
      AnnouncementPriority.important => AppColors.orange,
      AnnouncementPriority.normal => AppColors.blue,
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 15 : 20),
        onTap: () async {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(announcement.title),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(announcement.body),
                      if (announcement.attachments.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Anhänge',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        for (final attachment in announcement.attachments)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.attach_file_rounded),
                            title: Text(attachment.name),
                            subtitle: Text(attachment.url),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Gelesen'),
                ),
              ],
            ),
          );
          await onOpened();
        },
        child: Padding(
          padding: EdgeInsets.all(compact ? 11 : 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 36 : 46,
                height: compact ? 36 : 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(compact ? 11 : 14),
                ),
                child: Icon(Icons.campaign_rounded, color: color),
              ),
              SizedBox(width: compact ? 9 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: compact ? 5 : 8,
                      runSpacing: compact ? 4 : 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          announcement.title,
                          style: compact
                              ? Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900)
                              : Theme.of(context).textTheme.titleLarge,
                        ),
                        if (!announcement.isRead &&
                            announcement.status == AnnouncementStatus.published)
                          const Badge(label: Text('Neu')),
                        if (staffView)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            label: Text(_status(announcement.status)),
                          ),
                      ],
                    ),
                    SizedBox(height: compact ? 3 : 6),
                    Text(
                      announcement.body,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: compact ? 5 : 12),
                    Text(
                      '${announcement.authorName} · ${announcement.teamNames.join(', ')}'
                      '${staffView && announcement.readCount != null ? ' · ${announcement.readCount} gelesen' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: deletePermanently
                      ? 'Mitteilung endgültig löschen'
                      : 'Mitteilung löschen',
                  onPressed: onDelete,
                  color: Theme.of(context).colorScheme.error,
                  visualDensity:
                      compact ? VisualDensity.compact : VisualDensity.standard,
                  icon: Icon(deletePermanently
                      ? Icons.delete_forever_rounded
                      : Icons.delete_outline_rounded),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: compact ? 19 : 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationList extends ConsumerWidget {
  const _NotificationList({
    super.key,
    required this.canDelete,
    required this.onChanged,
  });

  final bool canDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return FutureBuilder<List<AppNotificationModel>>(
      future: ref.read(repositoryProvider).notifications(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: LogoLoadingPanel(message: 'Empfänger werden geladen …'),
          );
        }
        if (snapshot.hasError) return _ErrorCard(onRetry: onChanged);
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'Alles erledigt',
            message: 'Aktuell gibt es keine Benachrichtigungen.',
          );
        }
        final grouped = <FamilyNotificationGroup, List<AppNotificationModel>>{
          for (final group in FamilyNotificationGroup.values) group: [],
        };
        for (final item in items) {
          grouped[familyNotificationGroup(item)]!.add(item);
        }
        final unreadCount = items.where((item) => !item.isRead).length;
        final readCount = items.length - unreadCount;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (unreadCount > 0)
                  TextButton.icon(
                    onPressed: () async {
                      await ref
                          .read(repositoryProvider)
                          .markAllNotificationsRead();
                      ref.invalidate(liveNotificationsProvider);
                      ref.invalidate(parentDashboardSummaryProvider);
                      ref.invalidate(trainerDashboardSummaryProvider);
                      onChanged();
                    },
                    icon: const Icon(Icons.done_all_rounded),
                    label: const Text('Alle als gelesen markieren'),
                  ),
                if (readCount > 0)
                  OutlinedButton.icon(
                    key: const ValueKey('delete-read-notifications'),
                    onPressed: () => _deleteRead(
                      context,
                      ref,
                      readCount,
                    ),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text('Gelesene löschen ($readCount)'),
                  ),
              ],
            ),
            for (final group in FamilyNotificationGroup.values)
              if (grouped[group]!.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 7),
                  child: Row(
                    children: [
                      Icon(_groupIcon(group), size: 20, color: AppColors.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          familyNotificationGroupLabel(group),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${grouped[group]!.length}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final item in grouped[group]!)
                  Card(
                    margin: EdgeInsets.only(bottom: compact ? 5 : 8),
                    child: ListTile(
                      dense: compact,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: compact ? 9 : 14,
                        vertical: compact ? 2 : 8,
                      ),
                      leading: CircleAvatar(
                        radius: compact ? 17 : 20,
                        backgroundColor:
                            (item.isRead ? AppColors.muted : AppColors.blue)
                                .withValues(alpha: .12),
                        child: Icon(
                          Icons.notifications_rounded,
                          color: item.isRead ? AppColors.muted : AppColors.blue,
                        ),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.body,
                        maxLines: compact ? 2 : null,
                        overflow:
                            compact ? TextOverflow.ellipsis : TextOverflow.clip,
                      ),
                      trailing: canDelete
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!item.isRead)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 2),
                                    child: Icon(
                                      Icons.circle,
                                      size: 10,
                                      color: AppColors.orange,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Benachrichtigung löschen',
                                  icon:
                                      const Icon(Icons.delete_outline_rounded),
                                  color: Theme.of(context).colorScheme.error,
                                  visualDensity: compact
                                      ? VisualDensity.compact
                                      : VisualDensity.standard,
                                  onPressed: () => _delete(context, ref, item),
                                ),
                              ],
                            )
                          : item.isRead
                              ? null
                              : const Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: AppColors.orange,
                                ),
                      onTap: item.isRead
                          ? null
                          : () async {
                              await ref
                                  .read(repositoryProvider)
                                  .markNotificationRead(item.id);
                              onChanged();
                            },
                    ),
                  ),
              ],
          ],
        );
      },
    );
  }

  IconData _groupIcon(FamilyNotificationGroup group) => switch (group) {
        FamilyNotificationGroup.important => Icons.priority_high_rounded,
        FamilyNotificationGroup.matchday => Icons.sports_soccer_rounded,
        FamilyNotificationGroup.training => Icons.sports_rounded,
        FamilyNotificationGroup.club => Icons.campaign_rounded,
      };

  Future<void> _deleteRead(
    BuildContext context,
    WidgetRef ref,
    int readCount,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gelesene Benachrichtigungen löschen?'),
        content: Text(
          'Es werden ausschließlich die $readCount bereits gelesenen '
          'Benachrichtigungen aus deinem persönlichen Verlauf gelöscht. '
          'Ungelesene Benachrichtigungen bleiben vollständig erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Gelesene löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final deleted =
          await ref.read(repositoryProvider).deleteReadNotifications();
      ref.invalidate(liveNotificationsProvider);
      ref.invalidate(parentDashboardSummaryProvider);
      ref.invalidate(trainerDashboardSummaryProvider);
      onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted == 1
                ? 'Eine gelesene Benachrichtigung wurde gelöscht.'
                : '$deleted gelesene Benachrichtigungen wurden gelöscht.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gelesene Benachrichtigungen konnten nicht gelöscht werden.',
          ),
        ),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppNotificationModel item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Benachrichtigung löschen?'),
        content: Text(
          '„${item.title}“ wird nur aus deinem persönlichen '
          'Benachrichtigungsverlauf entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).deleteNotification(item.id);
      ref.invalidate(liveNotificationsProvider);
      onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Benachrichtigung wurde gelöscht.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Benachrichtigung konnte nicht gelöscht werden.'),
        ),
      );
    }
  }
}

class _NotificationSettings extends ConsumerStatefulWidget {
  const _NotificationSettings({super.key});

  @override
  ConsumerState<_NotificationSettings> createState() =>
      _NotificationSettingsState();
}

class _NotificationSettingsState extends ConsumerState<_NotificationSettings> {
  List<NotificationPreferenceModel>? _items;
  List<AdminPushDevice>? _devices;
  PushConfiguration? _configuration;
  WebPushStatus? _webPushStatus;
  bool _subscribing = false;
  bool _nativePushEnabled = false;
  bool _testingPush = false;
  String? _testingPushScenario;
  bool _changingDevice = false;
  AdminPushTestResult? _pushTestResult;
  final _deviceSearch = TextEditingController();
  String _deviceFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _deviceSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = ref.read(repositoryProvider);
    final isSuperAdmin =
        ref.read(authProvider).user?.role == UserRole.superAdmin;
    final results = await Future.wait<Object?>([
      repository.notificationPreferences(),
      repository.pushConfiguration(),
      nativePushService.currentTokenIfEnabled(),
      if (isSuperAdmin) repository.adminPushDevices(),
    ]);
    final configuration = results[1] as PushConfiguration;
    final webStatus = await getWebPushStatus(configuration.vapidPublicKey);
    if (mounted) {
      setState(() {
        _items = results[0] as List<NotificationPreferenceModel>;
        _configuration = results[1] as PushConfiguration;
        _nativePushEnabled = results[2] != null;
        _webPushStatus = webStatus;
        _devices = isSuperAdmin
            ? results[3] as List<AdminPushDevice>
            : const <AdminPushDevice>[];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final isSuperAdmin =
        ref.watch(authProvider).user?.role == UserRole.superAdmin;
    if (items == null) {
      return const Center(
        child: LogoLoadingPanel(message: 'Push-Geräte werden geladen …'),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Benachrichtigungen steuern',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Lege für jede Kategorie fest, was in der App und per Push erscheinen soll.',
            ),
            const SizedBox(height: 16),
            _PushRegistrationCard(
              configuration: _configuration,
              subscribing: _subscribing,
              nativeEnabled: _nativePushEnabled,
              webStatus: _webPushStatus,
              onSubscribe: _subscribe,
            ),
            if (isSuperAdmin) ...[
              const SizedBox(height: 14),
              _AdminPushTestCard(
                testing: _testingPush,
                testingScenario: _testingPushScenario,
                result: _pushTestResult,
                onTest: _testPushBroadcast,
                onScenarioTest: _testOwnPushScenario,
              ),
              const SizedBox(height: 14),
              AdminPushDeviceManagementCard(
                devices: _devices,
                searchController: _deviceSearch,
                filter: _deviceFilter,
                changing: _changingDevice,
                onSearchChanged: (_) => setState(() {}),
                onFilterChanged: (value) =>
                    setState(() => _deviceFilter = value),
                onRefresh: _loadAdminDevices,
                onToggle: _toggleAdminDevice,
                onDelete: _deleteAdminDevice,
                onDeleteDisabled: _deleteAllDisabledAdminDevices,
              ),
            ],
            const Divider(height: 32),
            for (var index = 0; index < items.length; index++)
              _PreferenceRow(
                value: items[index],
                onChanged: (value) => setState(() => _items![index] = value),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final saved = await ref
                    .read(repositoryProvider)
                    .saveNotificationPreferences(items);
                if (!mounted) return;
                setState(() => _items = saved);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Einstellungen gespeichert.')),
                );
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Einstellungen speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testPushBroadcast() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.campaign_rounded),
        title: const Text('Test-Push an alle senden?'),
        content: const Text(
          'Alle freigegebenen Benutzer mit einem aktiv registrierten '
          'Push-Gerät erhalten eine klar gekennzeichnete Testnachricht. '
          'Danach wird das Zustellergebnis angezeigt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Test senden'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _testingPush = true;
      _pushTestResult = null;
    });
    try {
      final result = await ref.read(repositoryProvider).sendAdminPushTest();
      if (!mounted) return;
      setState(() => _pushTestResult = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.subscriptions == 0
                ? 'Es ist noch kein aktives Push-Gerät registriert.'
                : '${result.sent} von ${result.subscriptions} Test-Pushnachrichten wurden vom Push-Dienst angenommen.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Der globale Push-Test konnte nicht ausgeführt werden.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _testingPush = false);
    }
  }

  Future<void> _testOwnPushScenario(String scenario) async {
    if (_testingPush || _testingPushScenario != null) return;
    setState(() {
      _testingPushScenario = scenario;
      _pushTestResult = null;
    });
    try {
      final result =
          await ref.read(repositoryProvider).sendAdminPushScenario(scenario);
      if (!mounted) return;
      setState(() => _pushTestResult = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.subscriptions == 0
                ? 'Für dein Konto ist kein aktives Push-Gerät registriert.'
                : '${result.sent} von ${result.subscriptions} eigenen Geräten haben das Testszenario angenommen.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Push-Testszenario konnte nicht gesendet werden.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _testingPushScenario = null);
    }
  }

  Future<void> _loadAdminDevices() async {
    setState(() => _devices = null);
    try {
      final devices = await ref.read(repositoryProvider).adminPushDevices();
      if (mounted) setState(() => _devices = devices);
    } catch (_) {
      if (!mounted) return;
      setState(() => _devices = const []);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Geräteliste konnte nicht geladen werden.')),
      );
    }
  }

  Future<void> _toggleAdminDevice(AdminPushDevice device) async {
    final activate = !device.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          activate
              ? Icons.notifications_active_rounded
              : Icons.notifications_off_rounded,
        ),
        title: Text(
            activate ? 'Gerät wieder aktivieren?' : 'Push-Gerät deaktivieren?'),
        content: Text(
          activate
              ? '${device.deviceName} von ${device.userName} darf danach wieder Pushnachrichten erhalten.'
              : '${device.deviceName} von ${device.userName} erhält danach keine Pushnachrichten mehr. Die Sperre bleibt auch nach einem App-Neustart bestehen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(activate ? 'Aktivieren' : 'Deaktivieren'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _changingDevice = true);
    try {
      await ref.read(repositoryProvider).setAdminPushDeviceState(
            device.id,
            isActive: activate,
          );
      await _loadAdminDevices();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activate
                ? 'Push-Gerät wurde aktiviert.'
                : 'Push-Gerät wurde dauerhaft deaktiviert.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Gerätestatus konnte nicht geändert werden.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _changingDevice = false);
    }
  }

  Future<void> _deleteAdminDevice(AdminPushDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.delete_forever_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('Gerät endgültig löschen?'),
        content: Text(
          '${device.deviceName} von ${device.userName} wird aus der Geräteverwaltung entfernt. '
          'Wird die App auf diesem Gerät später erneut verwendet, kann es sich neu registrieren. '
          'Für eine dauerhafte Push-Sperre verwende stattdessen „Deaktivieren“.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Endgültig löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _changingDevice = true);
    try {
      await ref.read(repositoryProvider).deleteAdminPushDevice(device.id);
      await _loadAdminDevices();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Push-Gerät wurde gelöscht.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Push-Gerät konnte nicht gelöscht werden.')),
      );
    } finally {
      if (mounted) setState(() => _changingDevice = false);
    }
  }

  Future<void> _deleteAllDisabledAdminDevices() async {
    final disabledCount =
        _devices?.where((device) => !device.isActive).length ?? 0;
    if (disabledCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Es gibt keine deaktivierten Geräte.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.delete_sweep_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('Alle deaktivierten Geräte löschen?'),
        content: Text(
          '${disabledCount == 1 ? 'Ein deaktiviertes Push-Gerät wird' : '$disabledCount deaktivierte Push-Geräte werden'} '
          'endgültig aus der Geräteverwaltung entfernt. '
          'Aktive Geräte bleiben erhalten. Wird die App auf einem entfernten Gerät später erneut verwendet, kann es sich neu registrieren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('Alle endgültig löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _changingDevice = true);
    try {
      final deleted = await ref
          .read(repositoryProvider)
          .deleteAllDisabledAdminPushDevices();
      await _loadAdminDevices();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted == 1
                ? 'Ein deaktiviertes Push-Gerät wurde gelöscht.'
                : '$deleted deaktivierte Push-Geräte wurden gelöscht.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Die deaktivierten Push-Geräte konnten nicht gelöscht werden.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _changingDevice = false);
    }
  }

  Future<void> _subscribe() async {
    setState(() => _subscribing = true);
    try {
      final repository = ref.read(repositoryProvider);
      if (nativePushService.supported) {
        if (_configuration?.androidConfigured != true) return;
        await repository.grantPushConsent();
        final token = await nativePushService.enable();
        if (token == null) {
          throw StateError('NOTIFICATION_PERMISSION_DENIED');
        }
        await repository.registerAndroidPushSubscription(token);
        if (mounted) setState(() => _nativePushEnabled = true);
      } else {
        final key = _configuration?.vapidPublicKey;
        if (key == null || !webPushSupported) return;
        final subscription = await subscribeToWebPush(key);
        await repository.grantPushConsent();
        await repository.registerWebPushSubscription(subscription);
        final status = await getWebPushStatus(key);
        if (mounted) setState(() => _webPushStatus = status);
      }
      ref.invalidate(currentDevicePushReadyProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Push-Benachrichtigungen sind jetzt aktiviert.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pushErrorMessage(error),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }

  String _pushErrorMessage(Object error) {
    final value = error.toString();
    if (value.contains('IOS_HOME_SCREEN_REQUIRED')) {
      return 'Öffne die Seite in Safari, wähle „Teilen“ und „Zum Home-Bildschirm“. '
          'Starte danach FC Teugn Talents über das neue App-Symbol.';
    }
    if (value.contains('PUSH_PERMISSION_DENIED')) {
      return 'Benachrichtigungen wurden abgelehnt. Bitte erlaube sie in den '
          'Browser- beziehungsweise Systemeinstellungen.';
    }
    if (value.contains('NOTIFICATION_PERMISSION_DENIED')) {
      return 'Bitte erlaube Benachrichtigungen in den Android-Einstellungen.';
    }
    if (value.contains('WEB_PUSH_UNSUPPORTED')) {
      return 'Dieser Browser unterstützt Web-Push auf diesem Gerät nicht.';
    }
    return 'Push konnte nicht aktiviert werden. Bitte Gerätefreigabe und Verbindung prüfen.';
  }
}

class _AdminPushTestCard extends StatelessWidget {
  const _AdminPushTestCard({
    required this.testing,
    required this.testingScenario,
    required this.result,
    required this.onTest,
    required this.onScenarioTest,
  });

  final bool testing;
  final String? testingScenario;
  final AdminPushTestResult? result;
  final VoidCallback onTest;
  final ValueChanged<String> onScenarioTest;

  @override
  Widget build(BuildContext context) {
    final value = result;
    final color = value == null
        ? AppColors.blue
        : value.allSent
            ? Colors.green
            : value.subscriptions == 0
                ? AppColors.orange
                : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Row(
                children: [
                  Icon(Icons.admin_panel_settings_rounded, color: color),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Systemweiter Push-Test',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              );
              final button = FilledButton.icon(
                onPressed: testing ? null : onTest,
                icon: testing
                    ? const LogoLoadingIndicator(
                        size: 22,
                        semanticsLabel: 'Pushnachricht wird versendet',
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(testing ? 'Sende …' : 'An alle testen'),
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 10),
                    button,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  button,
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          const Text(
            'Nur die Systemadministration kann eine Testnachricht an alle aktiv registrierten Geräte senden.',
          ),
          const SizedBox(height: 14),
          Text(
            'Tests nur an mich',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Prüfe konkrete Anzeige und Klickziel auf deinen eigenen aktiven Geräten.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scenario in _adminPushScenarios)
                OutlinedButton.icon(
                  onPressed: testing || testingScenario != null
                      ? null
                      : () => onScenarioTest(scenario.key),
                  icon: testingScenario == scenario.key
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(scenario.icon, size: 18),
                  label: Text(scenario.label),
                ),
            ],
          ),
          if (value != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${value.recipients} Empfänger')),
                Chip(
                    label:
                        Text('${value.sent}/${value.subscriptions} versendet')),
                Chip(label: Text('${value.webSubscriptions} Web')),
                Chip(label: Text('${value.androidSubscriptions} Android')),
                if (value.failed > 0)
                  Chip(label: Text('${value.failed} fehlgeschlagen')),
                if (value.pending > 0)
                  Chip(label: Text('${value.pending} ausstehend')),
              ],
            ),
            if (value.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Diagnose: ${value.errors.entries.map((item) => '${item.key} (${item.value})').join(', ')}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

const _adminPushScenarios = <({
  String key,
  String label,
  IconData icon,
})>[
  (key: 'TRAINING', label: 'Training', icon: Icons.sports_soccer_rounded),
  (key: 'MATCH', label: 'Spiel', icon: Icons.stadium_rounded),
  (key: 'LIVE_TICKER', label: 'Liveticker', icon: Icons.sensors_rounded),
  (key: 'NOMINATION', label: 'Nominierung', icon: Icons.groups_rounded),
  (key: 'REGISTRATION', label: 'Registrierung', icon: Icons.person_add_rounded),
  (key: 'MESSAGE', label: 'Nachricht', icon: Icons.forum_rounded),
  (key: 'SUPPORT', label: 'Support', icon: Icons.support_agent_rounded),
];

class AdminPushDeviceManagementCard extends StatelessWidget {
  const AdminPushDeviceManagementCard({
    super.key,
    required this.devices,
    required this.searchController,
    required this.filter,
    required this.changing,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onToggle,
    required this.onDelete,
    required this.onDeleteDisabled,
  });

  final List<AdminPushDevice>? devices;
  final TextEditingController searchController;
  final String filter;
  final bool changing;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onRefresh;
  final ValueChanged<AdminPushDevice> onToggle;
  final ValueChanged<AdminPushDevice> onDelete;
  final VoidCallback onDeleteDisabled;

  @override
  Widget build(BuildContext context) {
    final values = devices;
    final query = searchController.text.trim().toLowerCase();
    final filtered =
        values?.where((device) => _matches(device, query, filter)).toList() ??
            const <AdminPushDevice>[];
    final active = values
            ?.where((item) => item.health == PushDeviceHealth.active)
            .length ??
        0;
    final stale =
        values?.where((item) => item.health == PushDeviceHealth.stale).length ??
            0;
    final disabled = values
            ?.where((item) => item.health == PushDeviceHealth.disabled)
            .length ??
        0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.devices_other_rounded,
                  color: AppColors.blue,
                  size: 21,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Push-Geräte verwalten',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Status, Mitglied und letzter Kontakt',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Geräte neu laden',
                onPressed: changing ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              PopupMenuButton<String>(
                tooltip: 'Weitere Geräteaktionen',
                enabled: !changing,
                onSelected: (value) {
                  if (value == 'DELETE_DISABLED') onDeleteDisabled();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'DELETE_DISABLED',
                    enabled: disabled > 0,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.delete_sweep_rounded),
                      title: const Text('Alle deaktivierten Geräte löschen'),
                      subtitle: Text('$disabled Geräte'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _DeviceFilterChip(
                    label: 'Alle',
                    value: values?.length ?? 0,
                    selected: filter == 'ALL',
                    onSelected: changing ? null : () => onFilterChanged('ALL'),
                  ),
                  _DeviceFilterChip(
                    label: 'Aktiv',
                    value: active,
                    color: Colors.green,
                    selected: filter == 'ACTIVE',
                    onSelected:
                        changing ? null : () => onFilterChanged('ACTIVE'),
                  ),
                  _DeviceFilterChip(
                    label: 'Länger inaktiv',
                    value: stale,
                    color: AppColors.orange,
                    selected: filter == 'STALE',
                    onSelected:
                        changing ? null : () => onFilterChanged('STALE'),
                  ),
                  _DeviceFilterChip(
                    label: 'Deaktiviert',
                    value: disabled,
                    color: Theme.of(context).colorScheme.error,
                    selected: filter == 'DISABLED',
                    onSelected:
                        changing ? null : () => onFilterChanged('DISABLED'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Gerät oder Mitglied suchen',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Suche löschen',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        searchController.clear();
                        onSearchChanged('');
                      },
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          if (values == null)
            const Center(
              child: LogoLoadingPanel(
                message: 'Gerätestatus wird geladen …',
                compact: true,
              ),
            )
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('Keine Geräte für diesen Filter gefunden.'),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 900;
                final width = twoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    for (final device in filtered)
                      SizedBox(
                        width: width,
                        child: _CompactPushDeviceTile(
                          device: device,
                          changing: changing,
                          onToggle: () => onToggle(device),
                          onDelete: () => onDelete(device),
                        ),
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: 8),
          const Tooltip(
            message:
                '„Länger inaktiv“: seit mindestens 60 Tagen kein erfolgreicher Kontakt. '
                'Eine administrative Deaktivierung bleibt auch nach einem App-Neustart bestehen.',
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: AppColors.muted),
                SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Hinweise zu Status und Deaktivierung',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _matches(AdminPushDevice device, String query, String filter) {
    final statusMatches = switch (filter) {
      'ACTIVE' => device.isActive && !device.isStale,
      'STALE' => device.isStale,
      'DISABLED' => !device.isActive,
      _ => true,
    };
    if (!statusMatches || query.isEmpty) return statusMatches;
    return [
      device.deviceName,
      device.userName,
      device.userEmail,
      device.teamName,
      device.roleLabel,
      device.platform,
    ].any((value) => value.toLowerCase().contains(query));
  }
}

class _DeviceFilterChip extends StatelessWidget {
  const _DeviceFilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  final String label;
  final int value;
  final bool selected;
  final VoidCallback? onSelected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.blue;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        onSelected: onSelected == null ? null : (_) => onSelected!(),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: effectiveColor.withValues(alpha: .22)),
        selectedColor: effectiveColor.withValues(alpha: .14),
        avatar: Container(
          width: 7,
          height: 7,
          decoration:
              BoxDecoration(color: effectiveColor, shape: BoxShape.circle),
        ),
        label: Text('$label $value'),
      ),
    );
  }
}

class _CompactPushDeviceTile extends StatelessWidget {
  const _CompactPushDeviceTile({
    required this.device,
    required this.changing,
    required this.onToggle,
    required this.onDelete,
  });

  final AdminPushDevice device;
  final bool changing;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = switch (device.health) {
      PushDeviceHealth.active => Colors.green,
      PushDeviceHealth.stale => AppColors.orange,
      PushDeviceHealth.disabled => Theme.of(context).colorScheme.error,
    };
    final statusLabel = switch (device.health) {
      PushDeviceHealth.active => 'Aktiv',
      PushDeviceHealth.stale => 'Länger inaktiv',
      PushDeviceHealth.disabled => 'Deaktiviert',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 5, 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  device.isAndroid
                      ? Icons.phone_android_rounded
                      : Icons.language_rounded,
                  color: color,
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.deviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${device.userName} · ${device.teamName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      '${device.roleLabel} · ${device.userEmail}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: !changing,
                tooltip: 'Geräteaktionen',
                onSelected: (value) {
                  if (value == 'TOGGLE') onToggle();
                  if (value == 'DELETE') onDelete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'TOGGLE',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        device.isActive
                            ? Icons.notifications_off_rounded
                            : Icons.notifications_active_rounded,
                      ),
                      title:
                          Text(device.isActive ? 'Deaktivieren' : 'Aktivieren'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'DELETE',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_forever_rounded),
                      title: Text('Endgültig löschen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                device.isAndroid
                    ? Icons.phone_android_rounded
                    : Icons.language_rounded,
                size: 14,
                color: AppColors.muted,
              ),
              const SizedBox(width: 3),
              Text(
                device.isAndroid ? 'Android' : 'Web',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
              const SizedBox(width: 9),
              const Icon(Icons.schedule_rounded,
                  size: 14, color: AppColors.muted),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  _deviceDate(device.lastUsedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${device.deliveryCount} Push',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
          if (device.lastDeliveryError != null) ...[
            const SizedBox(height: 3),
            Text(
              'Letzter Push-Fehler: ${device.lastDeliveryError}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _deviceDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} · '
      '${two(local.hour)}:${two(local.minute)} Uhr';
}

class _PushRegistrationCard extends StatelessWidget {
  const _PushRegistrationCard({
    required this.configuration,
    required this.subscribing,
    required this.nativeEnabled,
    required this.webStatus,
    required this.onSubscribe,
  });

  final PushConfiguration? configuration;
  final bool subscribing;
  final bool nativeEnabled;
  final WebPushStatus? webStatus;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final native = nativePushService.supported;
    final configured = native
        ? configuration?.androidConfigured == true
        : configuration?.webPushConfigured == true;
    final status = webStatus ?? const WebPushStatus.unavailable();
    final enabled = native ? nativeEnabled : status.subscribed;
    final supported = native || status.supported;
    final canSubscribe = native || status.canSubscribe;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appColors.outline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final description = _pushDescription(
            native: native,
            configured: configured,
            enabled: enabled,
            status: status,
          );
          final information = Row(
            children: [
              const Icon(
                Icons.notifications_active_rounded,
                color: AppColors.blue,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Push auf diesem Gerät',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (!native && status.isIos)
                          const Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('iOS Web-App'),
                          ),
                      ],
                    ),
                    Text(description),
                  ],
                ),
              ),
            ],
          );
          final button = FilledButton.icon(
            onPressed: configured &&
                    supported &&
                    canSubscribe &&
                    !subscribing &&
                    !enabled
                ? onSubscribe
                : null,
            icon: Icon(
                enabled ? Icons.check_rounded : Icons.notifications_rounded),
            label: Text(
              enabled
                  ? 'Aktiv'
                  : subscribing
                      ? 'Aktiviere …'
                      : 'Aktivieren',
            ),
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                information,
                const SizedBox(height: 14),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: information),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }

  String _pushDescription({
    required bool native,
    required bool configured,
    required bool enabled,
    required WebPushStatus status,
  }) {
    if (!configured) {
      return native
          ? 'Android-Push muss für diese Umgebung noch eingerichtet werden.'
          : 'Web-Push muss für diese Umgebung noch eingerichtet werden.';
    }
    if (native) {
      return enabled
          ? 'Wichtige Hinweise werden auf diesem Android-Gerät zugestellt.'
          : 'Erhalte wichtige Hinweise auch bei geschlossener App.';
    }
    if (status.requiresHomeScreen) {
      return 'iPhone/iPad: Öffne „Teilen“ und wähle „Zum Home-Bildschirm“. '
          'Starte anschließend die installierte FC-Teugn-Web-App und aktiviere Push hier.';
    }
    if (!status.supported) {
      return 'Dieser Browser unterstützt Web-Push auf diesem Gerät nicht.';
    }
    if (status.permission == WebPushPermission.denied) {
      return 'Benachrichtigungen sind in den Browser- oder Systemeinstellungen blockiert.';
    }
    if (status.keyMismatch) {
      return 'Der Sicherheitsschlüssel wurde aktualisiert. Aktiviere Push auf diesem Gerät bitte erneut.';
    }
    if (enabled) {
      return 'Web-Push ist aktiv – Hinweise erscheinen auch bei geschlossener Web-App.';
    }
    return 'Erhalte wichtige Hinweise auch bei geschlossener Web-App.';
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.value, required this.onChanged});

  final NotificationPreferenceModel value;
  final ValueChanged<NotificationPreferenceModel> onChanged;

  @override
  Widget build(BuildContext context) {
    final isLiveTicker = value.category == NotificationCategory.liveTicker;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _category(value.category),
                style: TextStyle(
                  fontWeight: isLiveTicker ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
              if (isLiveTicker)
                const Text(
                  'Nur Spielstart, Tore, Gegentore und Spielende',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
            ],
          );
          final switches = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('In-App'),
              Switch(
                value: value.inApp,
                onChanged: (enabled) => onChanged(
                  NotificationPreferenceModel(
                    category: value.category,
                    inApp: enabled,
                    push: value.push,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Push'),
              Switch(
                value: value.push,
                onChanged: (enabled) => onChanged(
                  NotificationPreferenceModel(
                    category: value.category,
                    inApp: value.inApp,
                    push: enabled,
                  ),
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                Align(alignment: Alignment.centerRight, child: switches),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              switches,
            ],
          );
        },
      ),
    );
  }
}

class _ComposeAnnouncementDialog extends StatefulWidget {
  const _ComposeAnnouncementDialog({required this.organization});

  final OrganizationContext organization;

  @override
  State<_ComposeAnnouncementDialog> createState() =>
      _ComposeAnnouncementDialogState();
}

class _ComposeAnnouncementDialogState
    extends State<_ComposeAnnouncementDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _teamSearch = TextEditingController();
  late final Set<String> _teamIds = {widget.organization.currentTeam.id};
  AnnouncementAudience _audience = AnnouncementAudience.allMembers;
  AnnouncementPriority _priority = AnnouncementPriority.normal;
  AnnouncementStatus _status = AnnouncementStatus.published;
  bool _requireReadReceipt = false;
  bool _pushEnabled = true;
  DateTime? _publishAt;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _teamSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: screen.width < 700 ? 12 : 32,
        vertical: screen.height < 700 ? 12 : 28,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 840),
        child: SizedBox(
          width: 980,
          child: Column(
            children: [
              _buildHeader(context),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 760;
                    if (compact) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMessageEditor(context),
                            const SizedBox(height: 24),
                            _buildRecipientPanel(context, compact: true),
                          ],
                        ),
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: _buildMessageEditor(context),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: _buildRecipientPanel(context),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.yellow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.edit_notifications_rounded),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Neue Mitteilung',
                    style: Theme.of(context).textTheme.headlineSmall),
                Text(
                  'Nachricht verfassen, Empfänger wählen und Versand planen',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.muted),
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
    );
  }

  Widget _buildMessageEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          step: '1',
          title: 'Mitteilung verfassen',
          subtitle: 'Formuliere die Information kurz und eindeutig.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _title,
          onChanged: (_) => setState(() {}),
          maxLength: 160,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Titel',
            hintText: 'Worum geht es?',
            prefixIcon: Icon(Icons.title_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _body,
          onChanged: (_) => setState(() {}),
          minLines: 7,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: 'Nachricht',
            hintText: 'Alle wichtigen Informationen für die Empfänger …',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 22),
        Text('Versandoptionen', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 520;
            final fields = [
              DropdownButtonFormField<AnnouncementPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'Priorität',
                  prefixIcon: Icon(Icons.flag_rounded),
                ),
                items: AnnouncementPriority.values
                    .map((item) => DropdownMenuItem(
                          value: item,
                          child: Text(_priorityLabel(item)),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _priority = value!),
              ),
              DropdownButtonFormField<AnnouncementStatus>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Veröffentlichung',
                  prefixIcon: Icon(Icons.schedule_send_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                    value: AnnouncementStatus.published,
                    child: Text('Sofort veröffentlichen'),
                  ),
                  DropdownMenuItem(
                    value: AnnouncementStatus.scheduled,
                    child: Text('Zeitgesteuert'),
                  ),
                  DropdownMenuItem(
                    value: AnnouncementStatus.draft,
                    child: Text('Als Entwurf'),
                  ),
                ],
                onChanged: (value) => setState(() => _status = value!),
              ),
            ];
            return stack
                ? Column(children: [
                    fields[0],
                    const SizedBox(height: 12),
                    fields[1]
                  ])
                : Row(children: [
                    Expanded(child: fields[0]),
                    const SizedBox(width: 12),
                    Expanded(child: fields[1])
                  ]);
          },
        ),
        if (_status == AnnouncementStatus.scheduled) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickPublishTime,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(
                _publishAt == null
                    ? 'Veröffentlichungszeit wählen'
                    : 'Geplant für ${_dateTime(_publishAt!)}',
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _OptionSwitch(
          icon: Icons.mark_email_read_rounded,
          title: 'Lesebestätigung erfassen',
          subtitle: 'Zeigt, wie viele Empfänger die Mitteilung geöffnet haben.',
          value: _requireReadReceipt,
          onChanged: (value) => setState(() => _requireReadReceipt = value),
        ),
        const SizedBox(height: 8),
        _OptionSwitch(
          icon: Icons.notifications_active_rounded,
          title: 'Push-Benachrichtigung senden',
          subtitle:
              'Informiert die ausgewählten Empfänger direkt auf ihren Geräten.',
          value: _pushEnabled,
          onChanged: (value) => setState(() => _pushEnabled = value),
        ),
      ],
    );
  }

  Widget _buildRecipientPanel(BuildContext context, {bool compact = false}) {
    final query = _teamSearch.text.trim().toLowerCase();
    final teams = widget.organization.teams
        .where((team) => team.displayName.toLowerCase().contains(query))
        .toList();
    final list = Column(
      children: [
        for (final team in teams)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _TeamSelectionTile(
              name: team.displayName,
              selected: _teamIds.contains(team.id),
              onChanged: (selected) => setState(() {
                if (selected) {
                  _teamIds.add(team.id);
                } else {
                  _teamIds.remove(team.id);
                }
              }),
            ),
          ),
      ],
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          step: '2',
          title: 'Empfänger auswählen',
          subtitle: 'Bestimme Mannschaften und Zielgruppe.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _teamSearch,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Mannschaft suchen',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Suche löschen',
                    onPressed: () => setState(_teamSearch.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() {
                _teamIds
                    .addAll(widget.organization.teams.map((team) => team.id));
              }),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Alle'),
            ),
            TextButton.icon(
              onPressed:
                  _teamIds.isEmpty ? null : () => setState(_teamIds.clear),
              icon: const Icon(Icons.remove_done_rounded, size: 18),
              label: const Text('Keine'),
            ),
            const Spacer(),
            Text(
              '${_teamIds.length} gewählt',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (teams.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Keine Mannschaft gefunden.')),
          )
        else if (compact)
          list
        else
          Expanded(child: SingleChildScrollView(child: list)),
        const SizedBox(height: 12),
        DropdownButtonFormField<AnnouncementAudience>(
          initialValue: _audience,
          decoration: const InputDecoration(
            labelText: 'Zielgruppe',
            prefixIcon: Icon(Icons.groups_rounded),
          ),
          items: AnnouncementAudience.values
              .where((item) => item != AnnouncementAudience.individuals)
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(_audienceLabel(item)),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _audience = value!),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.yellow.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.yellow.withValues(alpha: .55)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.outgoing_mail, color: AppColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _teamIds.isEmpty
                      ? 'Wähle mindestens eine Mannschaft aus.'
                      : '${_teamIds.length} ${_teamIds.length == 1 ? 'Mannschaft' : 'Mannschaften'} · ${_audienceLabel(_audience)}${_pushEnabled ? ' · mit Push' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return compact ? content : SizedBox.expand(child: content);
  }

  Widget _buildFooter(BuildContext context) {
    final actionLabel = switch (_status) {
      AnnouncementStatus.draft => 'Entwurf speichern',
      AnnouncementStatus.scheduled => 'Mitteilung einplanen',
      _ => 'Jetzt veröffentlichen',
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackActions = constraints.maxWidth < 520 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.4;
        final cancel = TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        );
        final submit = FilledButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: Icon(_status == AnnouncementStatus.draft
              ? Icons.save_outlined
              : Icons.send_rounded),
          label: AdaptiveButtonLabel(actionLabel),
        );
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: stackActions ? 12 : 20,
            vertical: stackActions ? 10 : 14,
          ),
          child: stackActions
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    submit,
                    const SizedBox(height: 6),
                    cancel,
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pflichtfelder: Titel, Nachricht und mindestens eine Mannschaft',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.muted),
                      ),
                    ),
                    cancel,
                    const SizedBox(width: 8),
                    submit,
                  ],
                ),
        );
      },
    );
  }

  void _submit() => Navigator.pop(
        context,
        _AnnouncementDraft(
          title: _title.text.trim(),
          body: _body.text.trim(),
          teamIds: _teamIds.toList(),
          audience: _audience,
          priority: _priority,
          status: _status,
          publishAt: _publishAt,
          requireReadReceipt: _requireReadReceipt,
          pushEnabled: _pushEnabled,
        ),
      );

  bool get _canSubmit =>
      _title.text.trim().isNotEmpty &&
      _body.text.trim().isNotEmpty &&
      _teamIds.isNotEmpty &&
      (_status != AnnouncementStatus.scheduled || _publishAt != null);

  Future<void> _pickPublishTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    setState(() {
      _publishAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  final String step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.navy,
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionSwitch extends StatelessWidget {
  const _OptionSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appColors.outline),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        secondary: Icon(icon, color: AppColors.gold),
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _TeamSelectionTile extends StatelessWidget {
  const _TeamSelectionTile({
    required this.name,
    required this.selected,
    required this.onChanged,
  });

  final String name;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.yellow.withValues(alpha: .16)
          : context.appColors.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => onChanged(!selected),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.yellow
                      : context.appColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.groups_rounded, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Checkbox(
                value: selected,
                onChanged: (value) => onChanged(value ?? false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementDraft {
  const _AnnouncementDraft({
    required this.title,
    required this.body,
    required this.teamIds,
    required this.audience,
    required this.priority,
    required this.status,
    required this.publishAt,
    required this.requireReadReceipt,
    required this.pushEnabled,
  });

  final String title;
  final String body;
  final List<String> teamIds;
  final AnnouncementAudience audience;
  final AnnouncementPriority priority;
  final AnnouncementStatus status;
  final DateTime? publishAt;
  final bool requireReadReceipt;
  final bool pushEnabled;
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Daten konnten nicht geladen werden',
        message: 'Bitte prüfe die Verbindung und versuche es erneut.',
        action: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Erneut versuchen'),
        ),
      );
}

String _status(AnnouncementStatus value) => switch (value) {
      AnnouncementStatus.draft => 'Entwurf',
      AnnouncementStatus.scheduled => 'Geplant',
      AnnouncementStatus.published => 'Veröffentlicht',
      AnnouncementStatus.archived => 'Archiviert',
    };

String _audienceLabel(AnnouncementAudience value) => switch (value) {
      AnnouncementAudience.allMembers => 'Alle Mitglieder',
      AnnouncementAudience.parents => 'Eltern',
      AnnouncementAudience.players => 'Spieler',
      AnnouncementAudience.staff => 'Trainer & Organisation',
      AnnouncementAudience.individuals => 'Einzelne Personen',
    };

String _priorityLabel(AnnouncementPriority value) => switch (value) {
      AnnouncementPriority.normal => 'Normal',
      AnnouncementPriority.important => 'Wichtig',
      AnnouncementPriority.urgent => 'Dringend',
    };

String _category(NotificationCategory value) => switch (value) {
      NotificationCategory.event => 'Termine',
      NotificationCategory.eventReminder => 'Terminerinnerungen',
      NotificationCategory.announcement => 'Mitteilungen',
      NotificationCategory.nomination => 'Nominierungen',
      NotificationCategory.lineup => 'Aufstellungen',
      NotificationCategory.liveTicker => 'Live-Ticker',
      NotificationCategory.match => 'Spiele',
      NotificationCategory.registration => 'Registrierung',
      NotificationCategory.urgent => 'Dringende Hinweise',
      NotificationCategory.system => 'System',
    };

String _pitchRequestStatus(PitchConflictRequestStatus value) => switch (value) {
      PitchConflictRequestStatus.pending => 'Offen',
      PitchConflictRequestStatus.approved => 'Freigegeben',
      PitchConflictRequestStatus.declined => 'Abgelehnt',
      PitchConflictRequestStatus.callbackRequested => 'Rückruf gewünscht',
      PitchConflictRequestStatus.cancelled => 'Erledigt',
    };

String _dateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} Uhr';
