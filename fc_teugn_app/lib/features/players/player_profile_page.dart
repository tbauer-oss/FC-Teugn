import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/player.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../shared/page_scaffold.dart';

class PlayerProfilePage extends ConsumerWidget {
  const PlayerProfilePage({
    super.key,
    required this.playerId,
    required this.staffView,
  });

  final String playerId;
  final bool staffView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider(playerId));
    return PageScaffold(
      title: 'Spielerprofil',
      subtitle:
          'Stammdaten, Entwicklung und wichtige Informationen an einem Ort.',
      action: OutlinedButton.icon(
        onPressed: () =>
            context.go(staffView ? '/trainer/players' : '/parent/players'),
        icon: const Icon(Icons.arrow_back_rounded),
        label: const Text('Zur Mannschaft'),
      ),
      child: player.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => EmptyState(
          icon: Icons.person_off_outlined,
          title: 'Profil nicht erreichbar',
          message:
              'Das Spielerprofil konnte nicht geladen werden oder ist nicht freigegeben.',
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(playerProvider(playerId)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Erneut laden'),
          ),
        ),
        data: (data) => _ProfileContent(
          player: data,
          onRefresh: () {
            ref.invalidate(playerProvider(playerId));
            ref.invalidate(playersProvider);
          },
        ),
      ),
    );
  }
}

class _ProfileContent extends ConsumerWidget {
  const _ProfileContent({
    required this.player,
    required this.onRefresh,
  });

  final PlayerModel player;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _ProfileHero(
          player: player,
          onEdit: player.capabilities.canEdit
              ? () => _editBasics(context, ref)
              : null,
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            final left = Column(
              children: [
                _FactsCard(player: player),
                const SizedBox(height: 16),
                _GuardiansCard(
                  guardians: player.guardians,
                  onAdd: player.capabilities.canEdit
                      ? () => _addGuardian(context, ref)
                      : null,
                ),
                if (player.capabilities.canViewSensitive) ...[
                  const SizedBox(height: 16),
                  _MedicalCard(
                    player: player,
                    onEdit: player.capabilities.canEditSensitive
                        ? () => _editMedical(context, ref)
                        : null,
                    onAddContact: player.capabilities.canEditSensitive
                        ? () => _addEmergencyContact(context, ref)
                        : null,
                  ),
                ],
              ],
            );
            final right = Column(
              children: [
                _DevelopmentCard(
                  notes: player.developmentNotes,
                  onAdd: player.capabilities.canAddDevelopment
                      ? () => _addDevelopment(context, ref)
                      : null,
                ),
                if (player.capabilities.canViewSensitive) ...[
                  const SizedBox(height: 16),
                  _ConsentCard(
                    consents: player.consents,
                    editable: player.capabilities.canEditSensitive,
                    onChange: (type, status) =>
                        _changeConsent(context, ref, type, status),
                  ),
                ],
              ],
            );
            if (!wide) {
              return Column(
                children: [left, const SizedBox(height: 16), right],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: left),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: right),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _editBasics(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<PlayerModel>(
      context: context,
      builder: (context) => _EditBasicsDialog(player: player),
    );
    if (draft == null) return;
    await _run(
      context,
      () async {
        await ref.read(repositoryProvider).updatePlayer(draft);
      },
      'Stammdaten gespeichert.',
    );
  }

  Future<void> _editMedical(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_MedicalDraft>(
      context: context,
      builder: (context) =>
          _MedicalDialog(profile: player.medicalProfile),
    );
    if (draft == null) return;
    await _run(
      context,
      () => ref.read(repositoryProvider).updateMedicalProfile(
            playerId: player.id,
            allergies: draft.allergies,
            medications: draft.medications,
            conditions: draft.conditions,
            physicianName: draft.physicianName,
            physicianPhone: draft.physicianPhone,
            emergencyNotes: draft.emergencyNotes,
          ),
      'Gesundheitsdaten gespeichert.',
    );
  }

  Future<void> _addEmergencyContact(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final draft = await showDialog<_EmergencyDraft>(
      context: context,
      builder: (context) => const _EmergencyDialog(),
    );
    if (draft == null) return;
    await _run(
      context,
      () => ref.read(repositoryProvider).addEmergencyContact(
            playerId: player.id,
            name: draft.name,
            phone: draft.phone,
            relationship: draft.relationship,
            isAuthorizedPickup: draft.isAuthorizedPickup,
          ),
      'Notfallkontakt hinzugefügt.',
    );
  }

  Future<void> _addGuardian(BuildContext context, WidgetRef ref) async {
    final members = await ref.read(membersProvider.future);
    final parents = members
        .where((member) =>
            member.role == UserRole.parent &&
            member.status == AccountStatus.approved)
        .toList();
    if (!context.mounted) return;
    if (parents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Es gibt noch kein freigegebenes Elternkonto in dieser Mannschaft.',
          ),
        ),
      );
      return;
    }
    final draft = await showDialog<_GuardianDraft>(
      context: context,
      builder: (context) => _GuardianDialog(parents: parents),
    );
    if (draft == null) return;
    await _run(
      context,
      () => ref.read(repositoryProvider).assignParentPlayer(
            parentId: draft.parentId,
            playerId: player.id,
            relationship: draft.relationship,
            isLegalGuardian: draft.isLegalGuardian,
            canPickup: draft.canPickup,
            receivesCommunication: draft.receivesCommunication,
          ),
      'Sorgeberechtigte Person zugeordnet.',
    );
  }

  Future<void> _addDevelopment(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_DevelopmentDraft>(
      context: context,
      builder: (context) => const _DevelopmentDialog(),
    );
    if (draft == null) return;
    await _run(
      context,
      () => ref.read(repositoryProvider).addDevelopmentNote(
            playerId: player.id,
            title: draft.title,
            notes: draft.notes,
            category: draft.category,
            visibility: draft.visibility,
            rating: draft.rating,
          ),
      'Entwicklungsnotiz hinzugefügt.',
    );
  }

  Future<void> _changeConsent(
    BuildContext context,
    WidgetRef ref,
    String type,
    String status,
  ) async {
    await _run(
      context,
      () => ref.read(repositoryProvider).updateConsent(
            playerId: player.id,
            type: type,
            status: status,
          ),
      status == 'GRANTED'
          ? 'Einwilligung erteilt.'
          : 'Einwilligung widerrufen.',
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Änderung konnte nicht gespeichert werden.'),
          ),
        );
      }
    }
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.player, required this.onEdit});

  final PlayerModel player;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, Color(0xFF175A70)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: AppColors.orange,
            child: Text(
              '${player.firstName[0]}${player.lastName[0]}'.toUpperCase(),
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 310,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.fullName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    if (player.ageGroupCode != null)
                      '${player.ageGroupCode}-Jugend',
                    if (player.teamName != null) player.teamName!,
                    if (player.shirtNumber != null) '#${player.shirtNumber}',
                  ].join(' · '),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .68),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _StatusBadge(status: player.status),
          if (onEdit != null)
            OutlinedButton.icon(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: .35)),
              ),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Stammdaten bearbeiten'),
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final PlayerStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      PlayerStatus.active => 'Aktiv',
      PlayerStatus.injured => 'Verletzt',
      PlayerStatus.paused => 'Pausiert',
      PlayerStatus.left => 'Ausgetreten',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.player});

  final PlayerModel player;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Sportliches Profil',
      icon: Icons.sports_soccer_rounded,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _Fact(label: 'Rufname', value: player.displayName),
          _Fact(
            label: 'Geburtsdatum',
            value: player.birthDate == null ? 'Nicht hinterlegt' : _date(player.birthDate!),
          ),
          _Fact(label: 'Alter', value: player.age == null ? '–' : '${player.age} Jahre'),
          _Fact(label: 'Hauptposition', value: player.position ?? 'Noch offen'),
          _Fact(label: 'Nebenposition', value: player.secondaryPosition ?? '–'),
          _Fact(label: 'Starker Fuß', value: _foot(player.dominantFoot)),
          _Fact(label: 'Nationalität', value: player.nationality ?? '–'),
          _Fact(
            label: 'Im Verein seit',
            value: player.joinedAt == null ? '–' : _date(player.joinedAt!),
          ),
        ],
      ),
    );
  }

  String _foot(DominantFoot foot) => switch (foot) {
        DominantFoot.right => 'Rechts',
        DominantFoot.left => 'Links',
        DominantFoot.both => 'Beidfüßig',
        DominantFoot.unknown => 'Noch offen',
      };
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 9,
              letterSpacing: .8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuardiansCard extends StatelessWidget {
  const _GuardiansCard({required this.guardians, required this.onAdd});

  final List<GuardianModel> guardians;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Sorgeberechtigte',
      icon: Icons.family_restroom_rounded,
      trailing: onAdd == null
          ? null
          : TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Zuordnen'),
            ),
      child: guardians.isEmpty
          ? const Text(
              'Noch keine Sorgeberechtigten zugeordnet. Die Zuordnung erfolgt im Freigabecenter.',
            )
          : Column(
              children: [
                for (final guardian in guardians)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.background,
                      child: Icon(Icons.person_outline_rounded),
                    ),
                    title: Text(guardian.name),
                    subtitle: Text(
                      [
                        guardian.email,
                        if (guardian.phone != null) guardian.phone!,
                      ].join(' · '),
                    ),
                    trailing: guardian.isLegalGuardian
                        ? const Tooltip(
                            message: 'Sorgeberechtigt',
                            child: Icon(
                              Icons.verified_user_rounded,
                              color: AppColors.teal,
                            ),
                          )
                        : null,
                  ),
              ],
            ),
    );
  }
}

class _MedicalCard extends StatelessWidget {
  const _MedicalCard({
    required this.player,
    required this.onEdit,
    required this.onAddContact,
  });

  final PlayerModel player;
  final VoidCallback? onEdit;
  final VoidCallback? onAddContact;

  @override
  Widget build(BuildContext context) {
    final medical = player.medicalProfile;
    return _Section(
      title: 'Gesundheit & Notfall',
      icon: Icons.health_and_safety_rounded,
      trailing: onEdit == null
          ? null
          : IconButton(
              tooltip: 'Gesundheitsdaten bearbeiten',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (medical == null || medical.isEmpty)
            const Text('Keine medizinischen Hinweise hinterlegt.')
          else ...[
            _MedicalLine(label: 'Allergien', value: medical.allergies),
            _MedicalLine(label: 'Medikamente', value: medical.medications),
            _MedicalLine(label: 'Besonderheiten', value: medical.conditions),
            _MedicalLine(label: 'Notfallhinweis', value: medical.emergencyNotes),
          ],
          const Divider(height: 26),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Notfallkontakte',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (onAddContact != null)
                TextButton.icon(
                  onPressed: onAddContact,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Hinzufügen'),
                ),
            ],
          ),
          if (player.emergencyContacts.isEmpty)
            const Text('Noch kein Notfallkontakt hinterlegt.')
          else
            for (final contact in player.emergencyContacts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_in_talk_rounded),
                title: Text(contact.name),
                subtitle: Text(
                  [contact.relationship, contact.phone]
                      .whereType<String>()
                      .join(' · '),
                ),
                trailing: contact.isAuthorizedPickup
                    ? const Chip(label: Text('Abholberechtigt'))
                    : null,
              ),
        ],
      ),
    );
  }
}

class _MedicalLine extends StatelessWidget {
  const _MedicalLine({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value!)),
        ],
      ),
    );
  }
}

class _DevelopmentCard extends StatelessWidget {
  const _DevelopmentCard({required this.notes, required this.onAdd});

  final List<DevelopmentNote> notes;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Entwicklung',
      icon: Icons.trending_up_rounded,
      trailing: onAdd == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Beobachtung'),
            ),
      child: notes.isEmpty
          ? const Text(
              'Noch keine Entwicklungsbeobachtung dokumentiert.',
            )
          : Column(
              children: [
                for (var index = 0; index < notes.length; index++) ...[
                  _DevelopmentEntry(note: notes[index]),
                  if (index < notes.length - 1) const Divider(height: 24),
                ],
              ],
            ),
    );
  }
}

class _DevelopmentEntry extends StatelessWidget {
  const _DevelopmentEntry({required this.note});

  final DevelopmentNote note;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.teal.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.insights_rounded, color: AppColors.teal),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (note.rating != null)
                    Text(
                      '${List.filled(note.rating!, '●').join()}${List.filled(5 - note.rating!, '○').join()}',
                      style: const TextStyle(
                        color: AppColors.orange,
                        letterSpacing: 1,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(note.notes),
              const SizedBox(height: 6),
              Text(
                '${_category(note.category)} · ${note.authorName} · ${_date(note.observedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _category(String value) => const {
        'TECHNIQUE': 'Technik',
        'TACTICS': 'Taktik',
        'ATHLETIC': 'Athletik',
        'SOCIAL': 'Soziales',
        'GOALKEEPING': 'Torwart',
        'GENERAL': 'Allgemein',
      }[value] ??
      'Allgemein';
}

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({
    required this.consents,
    required this.editable,
    required this.onChange,
  });

  final List<PlayerConsent> consents;
  final bool editable;
  final void Function(String type, String status) onChange;

  static const types = {
    'PHOTO': 'Einzelfotos',
    'TEAM_PHOTO': 'Mannschaftsfotos',
    'TRANSPORT': 'Mitfahrten',
    'MEDICAL_DATA': 'Gesundheitsdaten',
    'COMMUNICATION': 'Digitale Kommunikation',
  };

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Einwilligungen',
      icon: Icons.fact_check_outlined,
      child: Column(
        children: [
          for (final entry in types.entries)
            Builder(
              builder: (context) {
                final current = _consent(entry.key);
                final granted = current?.status == 'GRANTED';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    granted
                        ? Icons.check_circle_rounded
                        : Icons.pending_outlined,
                    color: granted ? AppColors.teal : AppColors.orange,
                  ),
                  title: Text(entry.value),
                  subtitle: Text(
                    granted ? 'Erteilt' : 'Ausstehend oder widerrufen',
                  ),
                  trailing: editable
                      ? TextButton(
                          onPressed: () => onChange(
                            entry.key,
                            granted ? 'REVOKED' : 'GRANTED',
                          ),
                          child: Text(granted ? 'Widerrufen' : 'Erteilen'),
                        )
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }

  PlayerConsent? _consent(String type) {
    for (final consent in consents) {
      if (consent.type == type) return consent;
    }
    return null;
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _EditBasicsDialog extends StatefulWidget {
  const _EditBasicsDialog({required this.player});

  final PlayerModel player;

  @override
  State<_EditBasicsDialog> createState() => _EditBasicsDialogState();
}

class _EditBasicsDialogState extends State<_EditBasicsDialog> {
  late final TextEditingController firstName;
  late final TextEditingController lastName;
  late final TextEditingController preferredName;
  late final TextEditingController nationality;
  late final TextEditingController position;
  late final TextEditingController secondaryPosition;
  late final TextEditingController shirtNumber;
  late PlayerStatus status;
  late DominantFoot dominantFoot;

  @override
  void initState() {
    super.initState();
    final player = widget.player;
    firstName = TextEditingController(text: player.firstName);
    lastName = TextEditingController(text: player.lastName);
    preferredName = TextEditingController(text: player.preferredName);
    nationality = TextEditingController(text: player.nationality);
    position = TextEditingController(text: player.position);
    secondaryPosition = TextEditingController(text: player.secondaryPosition);
    shirtNumber =
        TextEditingController(text: player.shirtNumber?.toString() ?? '');
    status = player.status;
    dominantFoot = player.dominantFoot;
  }

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    preferredName.dispose();
    nationality.dispose();
    position.dispose();
    secondaryPosition.dispose();
    shirtNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Stammdaten bearbeiten'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: firstName,
                      decoration: const InputDecoration(labelText: 'Vorname'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: lastName,
                      decoration: const InputDecoration(labelText: 'Nachname'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: preferredName,
                      decoration: const InputDecoration(labelText: 'Rufname'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: nationality,
                      decoration:
                          const InputDecoration(labelText: 'Nationalität'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: position,
                      decoration:
                          const InputDecoration(labelText: 'Hauptposition'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: secondaryPosition,
                      decoration:
                          const InputDecoration(labelText: 'Nebenposition'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<DominantFoot>(
                      initialValue: dominantFoot,
                      decoration:
                          const InputDecoration(labelText: 'Starker Fuß'),
                      items: const [
                        DropdownMenuItem(
                          value: DominantFoot.unknown,
                          child: Text('Noch offen'),
                        ),
                        DropdownMenuItem(
                          value: DominantFoot.right,
                          child: Text('Rechts'),
                        ),
                        DropdownMenuItem(
                          value: DominantFoot.left,
                          child: Text('Links'),
                        ),
                        DropdownMenuItem(
                          value: DominantFoot.both,
                          child: Text('Beidfüßig'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => dominantFoot = value!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: shirtNumber,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Trikotnummer'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PlayerStatus>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(
                    value: PlayerStatus.active,
                    child: Text('Aktiv'),
                  ),
                  DropdownMenuItem(
                    value: PlayerStatus.injured,
                    child: Text('Verletzt'),
                  ),
                  DropdownMenuItem(
                    value: PlayerStatus.paused,
                    child: Text('Pausiert'),
                  ),
                  DropdownMenuItem(
                    value: PlayerStatus.left,
                    child: Text('Ausgetreten'),
                  ),
                ],
                onChanged: (value) => setState(() => status = value!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (firstName.text.trim().isEmpty ||
                lastName.text.trim().isEmpty) {
              return;
            }
            final original = widget.player;
            Navigator.pop(
              context,
              PlayerModel(
                id: original.id,
                teamId: original.teamId,
                firstName: firstName.text.trim(),
                lastName: lastName.text.trim(),
                preferredName: _optional(preferredName),
                birthDate: original.birthDate,
                nationality: _optional(nationality),
                position: _optional(position),
                secondaryPosition: _optional(secondaryPosition),
                dominantFoot: dominantFoot,
                shirtNumber: int.tryParse(shirtNumber.text),
                status: status,
                joinedAt: original.joinedAt,
                photoUrl: original.photoUrl,
                teamName: original.teamName,
                ageGroupCode: original.ageGroupCode,
                guardians: original.guardians,
                medicalProfile: original.medicalProfile,
                emergencyContacts: original.emergencyContacts,
                developmentNotes: original.developmentNotes,
                consents: original.consents,
                capabilities: original.capabilities,
              ),
            );
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _MedicalDialog extends StatefulWidget {
  const _MedicalDialog({required this.profile});

  final MedicalProfile? profile;

  @override
  State<_MedicalDialog> createState() => _MedicalDialogState();
}

class _MedicalDialogState extends State<_MedicalDialog> {
  late final TextEditingController allergies;
  late final TextEditingController medications;
  late final TextEditingController conditions;
  late final TextEditingController physicianName;
  late final TextEditingController physicianPhone;
  late final TextEditingController emergencyNotes;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    allergies = TextEditingController(text: profile?.allergies);
    medications = TextEditingController(text: profile?.medications);
    conditions = TextEditingController(text: profile?.conditions);
    physicianName = TextEditingController(text: profile?.physicianName);
    physicianPhone = TextEditingController(text: profile?.physicianPhone);
    emergencyNotes = TextEditingController(text: profile?.emergencyNotes);
  }

  @override
  void dispose() {
    allergies.dispose();
    medications.dispose();
    conditions.dispose();
    physicianName.dispose();
    physicianPhone.dispose();
    emergencyNotes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gesundheitsdaten'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: allergies,
                decoration: const InputDecoration(labelText: 'Allergien'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: medications,
                decoration: const InputDecoration(labelText: 'Medikamente'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: conditions,
                decoration:
                    const InputDecoration(labelText: 'Erkrankungen / Hinweise'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: physicianName,
                      decoration:
                          const InputDecoration(labelText: 'Kinderarzt'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: physicianPhone,
                      decoration: const InputDecoration(
                        labelText: 'Telefon Kinderarzt',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emergencyNotes,
                minLines: 2,
                maxLines: 4,
                decoration:
                    const InputDecoration(labelText: 'Notfallhinweise'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _MedicalDraft(
              allergies: _optional(allergies),
              medications: _optional(medications),
              conditions: _optional(conditions),
              physicianName: _optional(physicianName),
              physicianPhone: _optional(physicianPhone),
              emergencyNotes: _optional(emergencyNotes),
            ),
          ),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _EmergencyDialog extends StatefulWidget {
  const _EmergencyDialog();

  @override
  State<_EmergencyDialog> createState() => _EmergencyDialogState();
}

class _GuardianDialog extends StatefulWidget {
  const _GuardianDialog({required this.parents});

  final List<AppUser> parents;

  @override
  State<_GuardianDialog> createState() => _GuardianDialogState();
}

class _GuardianDialogState extends State<_GuardianDialog> {
  late String parentId;
  String relationship = 'GUARDIAN';
  bool isLegalGuardian = true;
  bool canPickup = true;
  bool receivesCommunication = true;

  @override
  void initState() {
    super.initState();
    parentId = widget.parents.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sorgeberechtigte Person zuordnen'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: parentId,
              decoration: const InputDecoration(labelText: 'Elternkonto'),
              items: [
                for (final parent in widget.parents)
                  DropdownMenuItem(
                    value: parent.id,
                    child: Text('${parent.name} · ${parent.email}'),
                  ),
              ],
              onChanged: (value) => setState(() => parentId = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: relationship,
              decoration: const InputDecoration(labelText: 'Beziehung'),
              items: const [
                DropdownMenuItem(value: 'MOTHER', child: Text('Mutter')),
                DropdownMenuItem(value: 'FATHER', child: Text('Vater')),
                DropdownMenuItem(
                  value: 'GUARDIAN',
                  child: Text('Sorgeberechtigte Person'),
                ),
                DropdownMenuItem(value: 'OTHER', child: Text('Andere')),
              ],
              onChanged: (value) => setState(() => relationship = value!),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: isLegalGuardian,
              title: const Text('Sorgeberechtigt'),
              onChanged: (value) =>
                  setState(() => isLegalGuardian = value ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: canPickup,
              title: const Text('Abholberechtigt'),
              onChanged: (value) =>
                  setState(() => canPickup = value ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: receivesCommunication,
              title: const Text('Erhält Teamkommunikation'),
              onChanged: (value) =>
                  setState(() => receivesCommunication = value ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _GuardianDraft(
              parentId: parentId,
              relationship: relationship,
              isLegalGuardian: isLegalGuardian,
              canPickup: canPickup,
              receivesCommunication: receivesCommunication,
            ),
          ),
          child: const Text('Zuordnen'),
        ),
      ],
    );
  }
}

class _EmergencyDialogState extends State<_EmergencyDialog> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final relationship = TextEditingController();
  bool isAuthorizedPickup = false;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    relationship.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notfallkontakt hinzufügen'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              decoration: const InputDecoration(labelText: 'Telefon *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: relationship,
              decoration: const InputDecoration(labelText: 'Beziehung'),
            ),
            CheckboxListTile(
              value: isAuthorizedPickup,
              contentPadding: EdgeInsets.zero,
              title: const Text('Abholberechtigt'),
              onChanged: (value) =>
                  setState(() => isAuthorizedPickup = value ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _EmergencyDraft(
                name: name.text.trim(),
                phone: phone.text.trim(),
                relationship: _optional(relationship),
                isAuthorizedPickup: isAuthorizedPickup,
              ),
            );
          },
          child: const Text('Hinzufügen'),
        ),
      ],
    );
  }
}

class _DevelopmentDialog extends StatefulWidget {
  const _DevelopmentDialog();

  @override
  State<_DevelopmentDialog> createState() => _DevelopmentDialogState();
}

class _DevelopmentDialogState extends State<_DevelopmentDialog> {
  final title = TextEditingController();
  final notes = TextEditingController();
  String category = 'GENERAL';
  String visibility = 'STAFF_ONLY';
  int? rating;

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Entwicklungsbeobachtung'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Titel *'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Bereich'),
                items: const [
                  DropdownMenuItem(
                    value: 'GENERAL',
                    child: Text('Allgemein'),
                  ),
                  DropdownMenuItem(
                    value: 'TECHNIQUE',
                    child: Text('Technik'),
                  ),
                  DropdownMenuItem(
                    value: 'TACTICS',
                    child: Text('Taktik'),
                  ),
                  DropdownMenuItem(
                    value: 'ATHLETIC',
                    child: Text('Athletik'),
                  ),
                  DropdownMenuItem(
                    value: 'SOCIAL',
                    child: Text('Soziales'),
                  ),
                  DropdownMenuItem(
                    value: 'GOALKEEPING',
                    child: Text('Torwart'),
                  ),
                ],
                onChanged: (value) => setState(() => category = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                minLines: 3,
                maxLines: 6,
                decoration:
                    const InputDecoration(labelText: 'Beobachtung *'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: rating,
                decoration: const InputDecoration(labelText: 'Einschätzung'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Ohne Bewertung')),
                  DropdownMenuItem(value: 1, child: Text('1 – Einstieg')),
                  DropdownMenuItem(value: 2, child: Text('2 – Aufbau')),
                  DropdownMenuItem(value: 3, child: Text('3 – Stabil')),
                  DropdownMenuItem(value: 4, child: Text('4 – Fortgeschritten')),
                  DropdownMenuItem(value: 5, child: Text('5 – Sehr stark')),
                ],
                onChanged: (value) => setState(() => rating = value),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'STAFF_ONLY',
                    label: Text('Nur Trainerteam'),
                  ),
                  ButtonSegment(
                    value: 'GUARDIANS_AND_STAFF',
                    label: Text('Mit Eltern teilen'),
                  ),
                ],
                selected: {visibility},
                onSelectionChanged: (value) =>
                    setState(() => visibility = value.first),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (title.text.trim().isEmpty || notes.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _DevelopmentDraft(
                title: title.text.trim(),
                notes: notes.text.trim(),
                category: category,
                visibility: visibility,
                rating: rating,
              ),
            );
          },
          child: const Text('Dokumentieren'),
        ),
      ],
    );
  }
}

class _MedicalDraft {
  const _MedicalDraft({
    this.allergies,
    this.medications,
    this.conditions,
    this.physicianName,
    this.physicianPhone,
    this.emergencyNotes,
  });

  final String? allergies;
  final String? medications;
  final String? conditions;
  final String? physicianName;
  final String? physicianPhone;
  final String? emergencyNotes;
}

class _EmergencyDraft {
  const _EmergencyDraft({
    required this.name,
    required this.phone,
    required this.isAuthorizedPickup,
    this.relationship,
  });

  final String name;
  final String phone;
  final String? relationship;
  final bool isAuthorizedPickup;
}

class _DevelopmentDraft {
  const _DevelopmentDraft({
    required this.title,
    required this.notes,
    required this.category,
    required this.visibility,
    this.rating,
  });

  final String title;
  final String notes;
  final String category;
  final String visibility;
  final int? rating;
}

class _GuardianDraft {
  const _GuardianDraft({
    required this.parentId,
    required this.relationship,
    required this.isLegalGuardian,
    required this.canPickup,
    required this.receivesCommunication,
  });

  final String parentId;
  final String relationship;
  final bool isLegalGuardian;
  final bool canPickup;
  final bool receivesCommunication;
}

String? _optional(TextEditingController controller) =>
    controller.text.trim().isEmpty ? null : controller.text.trim();

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
