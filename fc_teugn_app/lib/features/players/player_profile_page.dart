import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/football_options.dart';
import '../../core/models/organization.dart';
import '../../core/models/player.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../../core/widgets/responsive_form_dialog.dart';
import '../shared/page_scaffold.dart';
import 'widgets/digital_signature_capture.dart';

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
          onPhoto: player.capabilities.canManagePhoto
              ? (source) => _changePhoto(context, ref, source)
              : null,
          onRemovePhoto:
              player.photoUrl != null && player.capabilities.canManagePhoto
                  ? () => _removePhoto(context, ref)
                  : null,
          onDelete: player.capabilities.canEdit
              ? () => _deletePlayer(context, ref)
              : null,
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            if (constraints.maxWidth < 600) {
              return Column(
                children: [
                  _FactsCard(player: player),
                  const SizedBox(height: 12),
                  _SeasonStatisticsCard(player: player),
                  const SizedBox(height: 12),
                  _DevelopmentCard(
                    notes: player.developmentNotes,
                    onAdd: player.capabilities.canAddDevelopment
                        ? () => _addDevelopment(context, ref)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _GuardiansCard(
                    guardians: player.guardians,
                    onAdd: player.capabilities.canEdit
                        ? () => _addGuardian(context, ref)
                        : null,
                  ),
                  if (player.capabilities.canViewSensitive) ...[
                    const SizedBox(height: 12),
                    _MedicalCard(
                      player: player,
                      onEdit: player.capabilities.canEditSensitive
                          ? () => _editMedical(context, ref)
                          : null,
                      onAddContact: player.capabilities.canEditSensitive
                          ? () => _addEmergencyContact(context, ref)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _ConsentCard(
                      playerId: player.id,
                      consents: player.consents,
                      canSign: player.capabilities.canDigitallyConsent,
                      canManage: player.capabilities.canEditSensitive,
                      onRefresh: onRefresh,
                    ),
                    const SizedBox(height: 12),
                    _DocumentsCard(
                      playerId: player.id,
                      canManage: player.capabilities.canManageDocuments,
                    ),
                  ],
                ],
              );
            }
            final left = Column(
              children: [
                _FactsCard(player: player),
                const SizedBox(height: 16),
                _SeasonStatisticsCard(player: player),
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
                  const SizedBox(height: 16),
                  _DocumentsCard(
                    playerId: player.id,
                    canManage: player.capabilities.canManageDocuments,
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
                    playerId: player.id,
                    consents: player.consents,
                    canSign: player.capabilities.canDigitallyConsent,
                    canManage: player.capabilities.canEditSensitive,
                    onRefresh: onRefresh,
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
    final organization = await ref.read(organizationProvider.future);
    if (!context.mounted) return;
    final draft = await showDialog<PlayerModel>(
      context: context,
      builder: (context) => _EditBasicsDialog(
        player: player,
        teams: organization.teams,
      ),
    );
    if (draft == null) return;
    if (!context.mounted) return;
    await _run(
      context,
      () async {
        await ref.read(repositoryProvider).updatePlayer(draft);
      },
      'Stammdaten gespeichert.',
    );
  }

  Future<void> _deletePlayer(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spielerprofil löschen?'),
        content: Text(
          '${player.fullName} wird einschließlich der zugehörigen Profildaten gelöscht. '
          'Dieser Vorgang kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Endgültig löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).deletePlayer(player.id);
      ref.invalidate(playersProvider);
      if (context.mounted) context.go('/trainer/players');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Das Spielerprofil konnte nicht gelöscht werden. '
              'Prüfe bestehende Spiel- oder Statistikzuordnungen.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editMedical(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_MedicalDraft>(
      context: context,
      builder: (context) => _MedicalDialog(profile: player.medicalProfile),
    );
    if (draft == null) return;
    if (!context.mounted) return;
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
    if (!context.mounted) return;
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
            member.status == AccountStatus.approved &&
            member.role != UserRole.player &&
            !player.guardians.any((guardian) => guardian.id == member.id))
        .toList();
    if (!context.mounted) return;
    if (parents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Es gibt kein weiteres freigegebenes Mitglied, das als '
            'Elternteil zugeordnet werden kann.',
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
    if (!context.mounted) return;
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
    if (!context.mounted) return;
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

  Future<void> _changePhoto(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      requestFullMetadata: false,
    );
    if (picked == null) return;
    final sourceBytes = await picked.readAsBytes();
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Das Bildformat wird nicht unterstützt.')),
        );
      }
      return;
    }
    final oriented = img.bakeOrientation(decoded);
    final side =
        oriented.width < oriented.height ? oriented.width : oriented.height;
    final cropped = img.copyCrop(
      oriented,
      x: (oriented.width - side) ~/ 2,
      y: (oriented.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final resized = side > 1024
        ? img.copyResize(cropped, width: 1024, height: 1024)
        : cropped;
    final bytes = Uint8List.fromList(img.encodeJpg(resized, quality: 84));
    if (!context.mounted) return;
    try {
      final uploaded = await ref.read(repositoryProvider).uploadPlayerPhoto(
            playerId: player.id,
            bytes: bytes,
            fileName: '${player.id}.jpg',
          );
      if (uploaded.photoUrl == null) {
        throw StateError('Foto wurde nicht vom Backend bestätigt.');
      }
      ref.invalidate(playerProvider(player.id));
      ref.invalidate(playersProvider);
      final confirmed = await ref.read(playerProvider(player.id).future);
      if (confirmed.photoUrl == null) {
        throw StateError(
            'Foto konnte nach dem Speichern nicht geladen werden.');
      }
      onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spielerfoto geschützt gespeichert.')),
        );
      }
    } on DioException catch (error) {
      final response = error.response?.data;
      final message = response is Map<String, dynamic>
          ? response['message'] as String?
          : null;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(message ?? 'Foto konnte nicht gespeichert werden.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
            'Das Foto wurde nicht vollständig bestätigt. Bitte erneut versuchen.',
          )),
        );
      }
    }
  }

  Future<void> _removePhoto(BuildContext context, WidgetRef ref) async {
    await _run(
      context,
      () => ref.read(repositoryProvider).removePlayerPhoto(player.id),
      'Spielerfoto entfernt.',
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
  const _ProfileHero({
    required this.player,
    required this.onEdit,
    required this.onPhoto,
    required this.onRemovePhoto,
    required this.onDelete,
  });

  final PlayerModel player;
  final VoidCallback? onEdit;
  final ValueChanged<ImageSource>? onPhoto;
  final VoidCallback? onRemovePhoto;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final avatar = Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: compact ? 36 : 42,
              backgroundColor: AppColors.yellow,
              backgroundImage: player.photoUrl == null
                  ? null
                  : NetworkImage(player.photoUrl!),
              child: player.photoUrl == null
                  ? Text(
                      '${player.firstName[0]}${player.lastName[0]}'
                          .toUpperCase(),
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: compact ? 18 : 21,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : null,
            ),
            if (onPhoto != null)
              Positioned(
                right: -7,
                bottom: -7,
                child: PopupMenuButton<ImageSource>(
                  tooltip: 'Spielerfoto ändern',
                  onSelected: onPhoto,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: ImageSource.camera,
                      child: ListTile(
                        leading: Icon(Icons.photo_camera_outlined),
                        title: Text('Kamera'),
                      ),
                    ),
                    PopupMenuItem(
                      value: ImageSource.gallery,
                      child: ListTile(
                        leading: Icon(Icons.photo_library_outlined),
                        title: Text('Galerie'),
                      ),
                    ),
                  ],
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.edit_rounded, size: 17),
                  ),
                ),
              ),
          ],
        );
        final identity = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              player.fullName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: (compact
                      ? Theme.of(context).textTheme.headlineSmall
                      : Theme.of(context).textTheme.headlineMedium)
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (player.ageGroupCode != null)
                  '${player.ageGroupCode}-Jugend',
                if (player.teamName != null) player.teamName!,
                if (player.shirtNumber != null) '#${player.shirtNumber}',
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .72),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
        final statistics = [
          _CareerStatChip(
            icon: Icons.sports_soccer_rounded,
            label: '${player.goals} Tore',
            expanded: compact,
          ),
          _CareerStatChip(
            icon: Icons.assistant_direction_rounded,
            label: '${player.assists} Assists',
            expanded: compact,
          ),
          _CareerStatChip(
            icon: Icons.event_available_rounded,
            label: '${player.appearances} Einsätze',
            expanded: compact,
          ),
          _CareerStatChip(
            icon: Icons.timer_outlined,
            label: '${player.minutes} Minuten',
            expanded: compact,
          ),
        ];
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 18 : 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.black, Color(0xFF3A3400)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(compact ? 20 : 24),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        avatar,
                        const SizedBox(width: 16),
                        Expanded(child: identity),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _StatusBadge(status: player.status),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: constraints.maxWidth < 420 ? 1 : 2,
                      childAspectRatio: constraints.maxWidth < 420 ? 6.5 : 3.25,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: statistics,
                    ),
                    if (onEdit != null) ...[
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: onEdit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: .4),
                          ),
                        ),
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text('Stammdaten bearbeiten'),
                      ),
                    ],
                    if (onRemovePhoto != null || onDelete != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: PopupMenuButton<String>(
                          tooltip: 'Weitere Aktionen',
                          iconColor: Colors.white70,
                          onSelected: (value) {
                            if (value == 'removePhoto') onRemovePhoto?.call();
                            if (value == 'delete') onDelete?.call();
                          },
                          itemBuilder: (context) => [
                            if (onRemovePhoto != null)
                              const PopupMenuItem(
                                value: 'removePhoto',
                                child: ListTile(
                                  leading: Icon(Icons.delete_outline_rounded),
                                  title: Text('Foto entfernen'),
                                ),
                              ),
                            if (onDelete != null)
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: Icon(
                                    Icons.delete_forever_outlined,
                                    color: Colors.red.shade700,
                                  ),
                                  title: const Text('Spieler löschen'),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                )
              : Wrap(
                  spacing: 20,
                  runSpacing: 18,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    avatar,
                    SizedBox(width: 310, child: identity),
                    _StatusBadge(status: player.status),
                    ...statistics,
                    if (onEdit != null)
                      OutlinedButton.icon(
                        onPressed: onEdit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: .35),
                          ),
                        ),
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text('Stammdaten bearbeiten'),
                      ),
                    if (onRemovePhoto != null)
                      TextButton.icon(
                        onPressed: onRemovePhoto,
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.white70),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Foto entfernen'),
                      ),
                    if (onDelete != null)
                      TextButton.icon(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade200,
                        ),
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('Spieler löschen'),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _SeasonStatisticsCard extends StatelessWidget {
  const _SeasonStatisticsCard({required this.player});

  final PlayerModel player;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.query_stats_rounded, color: AppColors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Statistik nach Saison',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Gesamtwerte und historische Saisonwerte aus Aufstellungen und Liveticker.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              _PlayerStatisticRow(
                label: 'Gesamt',
                appearances: player.appearances,
                starts: player.starts,
                minutes: player.minutes,
                goals: player.goals,
                assists: player.assists,
                emphasized: true,
              ),
              if (player.statisticsBySeason.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text('Noch keine Saisonwerte vorhanden.'),
                )
              else
                for (final season in player.statisticsBySeason)
                  _PlayerStatisticRow(
                    label: season.seasonName,
                    appearances: season.appearances,
                    starts: season.starts,
                    minutes: season.minutes,
                    goals: season.goals,
                    assists: season.assists,
                  ),
            ],
          ),
        ),
      );
}

class _PlayerStatisticRow extends StatelessWidget {
  const _PlayerStatisticRow({
    required this.label,
    required this.appearances,
    required this.starts,
    required this.minutes,
    required this.goals,
    required this.assists,
    this.emphasized = false,
  });

  final String label;
  final int appearances;
  final int starts;
  final int minutes;
  final int goals;
  final int assists;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: emphasized
              ? AppColors.yellow.withValues(alpha: .16)
              : AppColors.navy.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: emphasized
                ? AppColors.yellow.withValues(alpha: .55)
                : AppColors.line,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final values =
                '$appearances Einsätze · $starts Startelf · $minutes Min. · '
                '$goals Tore · $assists Assists';
            if (constraints.maxWidth < 500) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(values, style: const TextStyle(color: AppColors.muted)),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(values, style: const TextStyle(color: AppColors.muted)),
              ],
            );
          },
        ),
      );
}

class _CareerStatChip extends StatelessWidget {
  const _CareerStatChip({
    required this.icon,
    required this.label,
    this.expanded = false,
  });

  final IconData icon;
  final String label;
  final bool expanded;

  @override
  Widget build(BuildContext context) => Container(
        width: expanded ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppColors.yellow),
            const SizedBox(width: 7),
            if (expanded)
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      );
}

class _DocumentsCard extends ConsumerStatefulWidget {
  const _DocumentsCard({
    required this.playerId,
    required this.canManage,
  });

  final String playerId;
  final bool canManage;

  @override
  ConsumerState<_DocumentsCard> createState() => _DocumentsCardState();
}

class _DocumentsCardState extends ConsumerState<_DocumentsCard> {
  late Future<List<PlayerDocument>> _documents;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _documents = ref.read(repositoryProvider).playerDocuments(widget.playerId);
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Geschützte Dokumente',
      icon: Icons.folder_shared_outlined,
      trailing: widget.canManage
          ? FilledButton.tonalIcon(
              onPressed: _upload,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Hochladen'),
            )
          : null,
      child: FutureBuilder<List<PlayerDocument>>(
        future: _documents,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Text(
              'Die Dokumente konnten nicht geladen werden.',
            );
          }
          final documents = snapshot.data ?? const [];
          if (documents.isEmpty) {
            return const Text(
              'Noch keine Einwilligung oder Vereinsunterlage hinterlegt.',
            );
          }
          return Column(
            children: [
              for (final document in documents)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 430;
                    final details = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          child: Icon(
                            document.file.contentType == 'application/pdf'
                                ? Icons.picture_as_pdf_outlined
                                : Icons.image_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                document.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${_documentType(document.type)} · '
                                'Version ${document.version} · '
                                '${_fileSize(document.file.size)}',
                                style: const TextStyle(color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    final actions = Wrap(
                      spacing: 2,
                      children: [
                        IconButton(
                          tooltip: 'Öffnen',
                          onPressed: () => launchUrl(
                            Uri.parse(document.file.downloadUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new_rounded),
                        ),
                        if (widget.canManage)
                          IconButton(
                            tooltip: 'Entfernen',
                            onPressed: () => _delete(document),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                      ],
                    );
                    return InkWell(
                      onTap: () => launchUrl(
                        Uri.parse(document.file.downloadUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: compact
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  details,
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: actions,
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: details),
                                  actions,
                                ],
                              ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _upload() async {
    final draft = await showDialog<_DocumentDraft>(
      context: context,
      builder: (context) => const _DocumentDialog(),
    );
    if (draft == null || !mounted) return;
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final file = selection?.files.single;
    if (file?.bytes == null || !mounted) return;
    if (file!.size > 4 * 1024 * 1024) {
      _message('Die Datei darf maximal 4 MB groß sein.');
      return;
    }
    try {
      await ref.read(repositoryProvider).uploadPlayerDocument(
            playerId: widget.playerId,
            bytes: file.bytes!,
            fileName: file.name,
            type: draft.type,
            title: draft.title,
          );
      if (!mounted) return;
      setState(_reload);
      _message('Dokument geschützt gespeichert.');
    } catch (_) {
      if (mounted) _message('Das Dokument konnte nicht gespeichert werden.');
    }
  }

  Future<void> _delete(PlayerDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dokument entfernen?'),
        content: Text(
          '${document.title} wird aus dem Spielerprofil entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(repositoryProvider).deletePlayerDocument(
            playerId: widget.playerId,
            documentId: document.id,
          );
      if (!mounted) return;
      setState(_reload);
      _message('Dokument entfernt.');
    } catch (_) {
      if (mounted) _message('Das Dokument konnte nicht entfernt werden.');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  String _fileSize(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).ceil()} KB';

  String _documentType(String type) => switch (type) {
        'PHOTO_CONSENT' => 'Fotoeinwilligung',
        'PRIVACY_CONSENT' => 'Datenschutz',
        'PARTICIPATION_PERMISSION' => 'Teilnahmeerlaubnis',
        'SWIMMING_PERMISSION' => 'Schwimmerlaubnis',
        'DECLARATION' => 'Erklärung',
        'TEAM_DOCUMENT' => 'Mannschaftsdokument',
        _ => 'Sonstiges',
      };
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 300 ? 1 : 2;
          final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Fact(
                width: width,
                label: 'Rufname',
                value: player.displayName,
              ),
              _Fact(
                width: width,
                label: 'Geburtsdatum',
                value: player.birthDate == null
                    ? 'Nicht hinterlegt'
                    : _date(player.birthDate!),
              ),
              _Fact(
                width: width,
                label: 'Alter',
                value: player.age == null ? '–' : '${player.age} Jahre',
              ),
              _Fact(
                width: width,
                label: 'Hauptposition',
                value: player.position ?? 'Noch offen',
              ),
              _Fact(
                width: width,
                label: 'Nebenposition',
                value: player.secondaryPosition ?? '–',
              ),
              _Fact(
                width: width,
                label: 'Starker Fuß',
                value: _foot(player.dominantFoot),
              ),
              _Fact(
                width: width,
                label: 'Nationalität',
                value: player.nationality ?? '–',
              ),
              _Fact(
                width: width,
                label: 'Im Verein seit',
                value: player.joinedAt == null ? '–' : _date(player.joinedAt!),
              ),
            ],
          );
        },
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
  const _Fact({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
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
                    title: Text(
                      '${guardian.name} · '
                      '${guardianRelationshipLabel(guardian.relationship)}',
                    ),
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
            _MedicalLine(
                label: 'Notfallhinweis', value: medical.emergencyNotes),
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.phone_in_talk_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contact.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            [contact.relationship, contact.phone]
                                .whereType<String>()
                                .join(' · '),
                          ),
                          if (contact.isAuthorizedPickup)
                            const Padding(
                              padding: EdgeInsets.only(top: 5),
                              child: Chip(label: Text('Abholberechtigt')),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
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

  String _category(String value) =>
      const {
        'TECHNIQUE': 'Technik',
        'TACTICS': 'Taktik',
        'ATHLETIC': 'Athletik',
        'SOCIAL': 'Soziales',
        'GOALKEEPING': 'Torwart',
        'GENERAL': 'Allgemein',
      }[value] ??
      'Allgemein';
}

class _ConsentCard extends ConsumerWidget {
  const _ConsentCard({
    required this.playerId,
    required this.consents,
    required this.canSign,
    required this.canManage,
    required this.onRefresh,
  });

  final String playerId;
  final List<PlayerConsent> consents;
  final bool canSign;
  final bool canManage;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(consentTemplatesProvider);
    return _Section(
      title: 'Einwilligungen & Vorlagen',
      icon: Icons.fact_check_outlined,
      child: templates.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => EmptyState(
          icon: Icons.description_outlined,
          title: 'Vorlagen nicht erreichbar',
          message: 'Bitte die Einwilligungsvorlagen erneut laden.',
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(consentTemplatesProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Neu laden'),
          ),
        ),
        data: (items) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Jede Einwilligung ist freiwillig, einzeln wählbar und jederzeit mit Wirkung für die Zukunft widerrufbar.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            for (final template in items) ...[
              _ConsentTile(
                template: template,
                consent: _consent(template.type),
                canSign: canSign,
                canManage: canManage,
                onTemplate: () => _downloadTemplate(context, ref, template),
                onSign: () => _sign(context, ref, template),
                onRevoke: () => _revoke(context, ref, template),
                onEvidence: (evidence) =>
                    _downloadEvidence(context, ref, template, evidence),
              ),
              if (template != items.last) const Divider(height: 22),
            ],
            const SizedBox(height: 10),
            const DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFFFF8D8),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Die Vorlagen sind DSGVO-orientiert und für die Vereinsprüfung vorbereitet. Vor dem verbindlichen Einsatz müssen Vereinsanschrift, Kommunikationsdienste und die Datenschutzinformationen durch den Verein aktuell gehalten und fachlich geprüft werden.',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PlayerConsent? _consent(String type) {
    for (final consent in consents) {
      if (consent.type == type) return consent;
    }
    return null;
  }

  Future<void> _downloadTemplate(
    BuildContext context,
    WidgetRef ref,
    ConsentTemplate template,
  ) async {
    await _action(
      context,
      () => ref.read(repositoryProvider).downloadConsentTemplate(template),
      'PDF-Vorlage wurde bereitgestellt.',
    );
  }

  Future<void> _downloadEvidence(
    BuildContext context,
    WidgetRef ref,
    ConsentTemplate template,
    PlayerConsentEvidence evidence,
  ) async {
    await _action(
      context,
      () => ref.read(repositoryProvider).downloadConsentEvidence(
            playerId: playerId,
            type: template.type,
            evidence: evidence,
          ),
      'Signierter Nachweis wurde bereitgestellt.',
    );
  }

  Future<void> _sign(
    BuildContext context,
    WidgetRef ref,
    ConsentTemplate template,
  ) async {
    if (!canSign) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Digital unterschreiben kann nur eine zugeordnete sorgeberechtigte Person.',
          ),
        ),
      );
      return;
    }
    final draft = await showDialog<_DigitalConsentDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DigitalConsentDialog(template: template),
    );
    if (draft == null || !context.mounted) return;
    await _action(
      context,
      () => ref.read(repositoryProvider).signConsent(
            playerId: playerId,
            type: template.type,
            templateVersion: template.version,
            selections: draft.selections,
            signatureData: draft.signatureData,
            guardianAuthorityConfirmed: true,
            explicitConsent: template.explicit,
            note: draft.note,
            childAssentName: draft.childAssentName,
          ),
      'Einwilligung wurde digital unterschrieben und nachweisbar gespeichert.',
      refresh: true,
    );
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    ConsentTemplate template,
  ) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Einwilligung widerrufen?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Der Widerruf gilt für die Zukunft. Bereits rechtmäßig erfolgte Verarbeitungen bleiben davon unberührt.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reason,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Grund (optional)',
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
            child: const Text('Widerrufen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _action(
      context,
      () => ref.read(repositoryProvider).revokeConsent(
            playerId: playerId,
            type: template.type,
            reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
          ),
      'Einwilligung wurde widerrufen.',
      refresh: true,
    );
  }

  Future<void> _action(
    BuildContext context,
    Future<void> Function() action,
    String success, {
    bool refresh = false,
  }) async {
    try {
      await action();
      if (!context.mounted) return;
      if (refresh) onRefresh();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    } on DioException catch (error) {
      if (!context.mounted) return;
      final data = error.response?.data;
      final message =
          data is Map<String, dynamic> ? data['message'] as String? : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(message ?? 'Aktion konnte nicht ausgeführt werden.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktion konnte nicht ausgeführt werden.')),
      );
    }
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.template,
    required this.consent,
    required this.canSign,
    required this.canManage,
    required this.onTemplate,
    required this.onSign,
    required this.onRevoke,
    required this.onEvidence,
  });

  final ConsentTemplate template;
  final PlayerConsent? consent;
  final bool canSign;
  final bool canManage;
  final VoidCallback onTemplate;
  final VoidCallback onSign;
  final VoidCallback onRevoke;
  final void Function(PlayerConsentEvidence evidence) onEvidence;

  @override
  Widget build(BuildContext context) {
    final granted = consent?.status == 'GRANTED';
    final revoked = consent?.status == 'REVOKED';
    final evidence = consent?.latestEvidence;
    final date = consent?.grantedAt == null
        ? null
        : MaterialLocalizations.of(context)
            .formatMediumDate(consent!.grantedAt!.toLocal());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: granted
                    ? AppColors.teal.withValues(alpha: .12)
                    : AppColors.orange.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                granted
                    ? Icons.verified_user_rounded
                    : revoked
                        ? Icons.cancel_outlined
                        : Icons.pending_actions_outlined,
                color: granted ? AppColors.teal : AppColors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.shortTitle,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    granted
                        ? 'Erteilt${date == null ? '' : ' am $date'}'
                        : revoked
                            ? 'Widerrufen'
                            : 'Noch nicht erteilt',
                    style: TextStyle(
                      color: granted ? AppColors.teal : AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: onTemplate,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Vorlage'),
            ),
            if (canSign && !granted)
              FilledButton.icon(
                onPressed: onSign,
                icon: const Icon(Icons.draw_outlined, size: 18),
                label: const Text('Digital ausfüllen'),
              ),
            if (evidence != null && evidence.action == 'GRANTED')
              OutlinedButton.icon(
                onPressed: () => onEvidence(evidence),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Nachweis'),
              ),
            if (granted && (canSign || canManage))
              TextButton.icon(
                onPressed: onRevoke,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Widerrufen'),
              ),
          ],
        ),
      ],
    );
  }
}

class _DigitalConsentDraft {
  const _DigitalConsentDraft({
    required this.selections,
    required this.signatureData,
    this.note,
    this.childAssentName,
  });

  final List<String> selections;
  final Map<String, dynamic> signatureData;
  final String? note;
  final String? childAssentName;
}

class _DigitalConsentDialog extends StatefulWidget {
  const _DigitalConsentDialog({required this.template});

  final ConsentTemplate template;

  @override
  State<_DigitalConsentDialog> createState() => _DigitalConsentDialogState();
}

class _DigitalConsentDialogState extends State<_DigitalConsentDialog> {
  final selected = <String>{};
  final note = TextEditingController();
  final childAssent = TextEditingController();
  Map<String, dynamic>? signatureData;
  bool authorityConfirmed = false;
  bool informationConfirmed = false;
  bool explicitConfirmed = false;

  @override
  void dispose() {
    note.dispose();
    childAssent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 40,
        vertical: compact ? 12 : 28,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 24,
                16,
                8,
                10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.template.shortTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Schließen',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 16 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.template.purpose),
                    const SizedBox(height: 8),
                    Text(
                      'Rechtsgrundlage: ${widget.template.legalBasis}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Wofür gilt die Einwilligung?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    for (final option in widget.template.options)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: selected.contains(option.id),
                        title: Text(option.label),
                        subtitle: option.description == null
                            ? null
                            : Text(option.description!),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            selected.add(option.id);
                          } else {
                            selected.remove(option.id);
                          }
                        }),
                      ),
                    if (widget.template.risks != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3D5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.template.risks!,
                          style: const TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: note,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Ergänzung oder Einschränkung (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: childAssent,
                      decoration: const InputDecoration(
                        labelText:
                            'Zustimmung des Kindes / Jugendlichen (optional)',
                        helperText:
                            'Empfohlen, sobald das Kind die Bedeutung selbst verstehen kann.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: authorityConfirmed,
                      title: const Text(
                        'Ich bin sorgeberechtigt oder nachweislich bevollmächtigt.',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) => setState(
                        () => authorityConfirmed = value == true,
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: informationConfirmed,
                      title: const Text(
                        'Ich habe Zweck, Empfänger, Speicherdauer, Freiwilligkeit und Widerrufsrecht verstanden.',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) => setState(
                        () => informationConfirmed = value == true,
                      ),
                    ),
                    if (widget.template.explicit)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: explicitConfirmed,
                        title: const Text(
                          'Ich willige ausdrücklich in die Verarbeitung der ausgewählten Gesundheitsdaten ein.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) => setState(
                          () => explicitConfirmed = value == true,
                        ),
                      ),
                    const SizedBox(height: 10),
                    DigitalSignatureCapture(
                      signatureData: signatureData,
                      onChanged: (value) => setState(
                        () => signatureData = value,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Vorlagenversion ${widget.template.version} · Der signierte Inhalt, Zeitpunkt und eine SHA-256-Nachweis-ID werden unveränderbar protokolliert.',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _submit,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text('Verbindlich unterschreiben'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Abbrechen'),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Abbrechen'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _submit,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text('Verbindlich unterschreiben'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (selected.isEmpty) {
      _message('Bitte mindestens einen Umfang auswählen.');
      return;
    }
    if (!authorityConfirmed || !informationConfirmed) {
      _message('Bitte die erforderlichen Bestätigungen aktivieren.');
      return;
    }
    if (widget.template.explicit && !explicitConfirmed) {
      _message('Bitte die ausdrückliche Einwilligung bestätigen.');
      return;
    }
    if (signatureData == null) {
      _message('Bitte eine Unterschrift hinzufügen und übernehmen.');
      return;
    }
    Navigator.pop(
      context,
      _DigitalConsentDraft(
        selections: selected.toList(),
        signatureData: signatureData!,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
        childAssentName:
            childAssent.text.trim().isEmpty ? null : childAssent.text.trim(),
      ),
    );
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
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
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = trailing != null && constraints.maxWidth < 360;
                final heading = Row(
                  children: [
                    Icon(icon, color: AppColors.blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (!stacked && trailing != null) trailing!,
                  ],
                );
                return stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          heading,
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: trailing!,
                          ),
                        ],
                      )
                    : heading;
              },
            ),
            SizedBox(height: compact ? 14 : 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _EditBasicsDialog extends StatefulWidget {
  const _EditBasicsDialog({
    required this.player,
    required this.teams,
  });

  final PlayerModel player;
  final List<TeamSummary> teams;

  @override
  State<_EditBasicsDialog> createState() => _EditBasicsDialogState();
}

class _EditBasicsDialogState extends State<_EditBasicsDialog> {
  late final TextEditingController firstName;
  late final TextEditingController lastName;
  late final TextEditingController preferredName;
  late final TextEditingController nationality;
  late final TextEditingController shirtNumber;
  String? position;
  String? secondaryPosition;
  late PlayerStatus status;
  late DominantFoot dominantFoot;
  late String teamId;

  @override
  void initState() {
    super.initState();
    final player = widget.player;
    firstName = TextEditingController(text: player.firstName);
    lastName = TextEditingController(text: player.lastName);
    preferredName = TextEditingController(text: player.preferredName);
    nationality = TextEditingController(text: player.nationality);
    position = player.position;
    secondaryPosition = player.secondaryPosition;
    shirtNumber =
        TextEditingController(text: player.shirtNumber?.toString() ?? '');
    status = player.status;
    dominantFoot = player.dominantFoot;
    teamId = widget.teams.any((team) => team.id == player.teamId)
        ? player.teamId!
        : widget.teams.first.id;
  }

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    preferredName.dispose();
    nationality.dispose();
    shirtNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void save() {
      if (firstName.text.trim().isEmpty || lastName.text.trim().isEmpty) return;
      final original = widget.player;
      Navigator.pop(
        context,
        PlayerModel(
          id: original.id,
          teamId: teamId,
          firstName: firstName.text.trim(),
          lastName: lastName.text.trim(),
          preferredName: _optional(preferredName),
          birthDate: original.birthDate,
          nationality: _optional(nationality),
          position: position,
          secondaryPosition: secondaryPosition,
          dominantFoot: dominantFoot,
          shirtNumber: int.tryParse(shirtNumber.text),
          status: status,
          joinedAt: original.joinedAt,
          photoUrl: original.photoUrl,
          teamName:
              widget.teams.where((team) => team.id == teamId).firstOrNull?.name,
          ageGroupCode: widget.teams
              .where((team) => team.id == teamId)
              .firstOrNull
              ?.ageGroup
              .code,
          guardians: original.guardians,
          medicalProfile: original.medicalProfile,
          emergencyContacts: original.emergencyContacts,
          developmentNotes: original.developmentNotes,
          consents: original.consents,
          capabilities: original.capabilities,
        ),
      );
    }

    return ResponsiveFormDialog(
      title: 'Stammdaten bearbeiten',
      subtitle: 'Persönliche Angaben und Fußballprofil übersichtlich pflegen.',
      onSave: save,
      children: [
        ResponsiveFormSection(
          title: 'Zuordnung',
          icon: Icons.groups_rounded,
          children: [
            DropdownButtonFormField<String>(
              initialValue: teamId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Jugend / Mannschaft',
                prefixIcon: Icon(Icons.groups_rounded),
                helperText: 'Administratoren können Spieler hier verschieben.',
              ),
              items: [
                for (final team in widget.teams)
                  DropdownMenuItem(
                    value: team.id,
                    child: Text(team.displayName),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => teamId = value);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        ResponsiveFormSection(
          title: 'Persönliche Daten',
          icon: Icons.badge_outlined,
          children: [
            ResponsiveFormRow(
              children: [
                TextField(
                  controller: firstName,
                  decoration: const InputDecoration(labelText: 'Vorname'),
                ),
                TextField(
                  controller: lastName,
                  decoration: const InputDecoration(labelText: 'Nachname'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ResponsiveFormRow(
              children: [
                TextField(
                  controller: preferredName,
                  decoration: const InputDecoration(labelText: 'Rufname'),
                ),
                TextField(
                  controller: nationality,
                  decoration: const InputDecoration(labelText: 'Nationalität'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        ResponsiveFormSection(
          title: 'Fußballprofil',
          icon: Icons.sports_soccer_rounded,
          children: [
            ResponsiveFormRow(
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: position,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Hauptposition'),
                  items: footballOptionItems(
                    options: footballPositions,
                    emptyLabel: 'Noch offen',
                    currentValue: position,
                    showCode: true,
                  ),
                  onChanged: (value) => setState(() => position = value),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: secondaryPosition,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Nebenposition'),
                  items: footballOptionItems(
                    options: footballPositions,
                    emptyLabel: 'Keine Nebenposition',
                    currentValue: secondaryPosition,
                    showCode: true,
                  ),
                  onChanged: (value) =>
                      setState(() => secondaryPosition = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ResponsiveFormRow(
              children: [
                DropdownButtonFormField<DominantFoot>(
                  initialValue: dominantFoot,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Starker Fuß'),
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
                  onChanged: (value) => setState(() => dominantFoot = value!),
                ),
                TextField(
                  controller: shirtNumber,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Trikotnummer'),
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
              _ResponsiveFields(
                children: [
                  TextField(
                    controller: physicianName,
                    decoration: const InputDecoration(labelText: 'Kinderarzt'),
                  ),
                  TextField(
                    controller: physicianPhone,
                    decoration: const InputDecoration(
                      labelText: 'Telefon Kinderarzt',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emergencyNotes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notfallhinweise'),
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
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Mitglied / Elternteil',
                helperText:
                    'Die bestehende Hauptrolle und ihre Rechte bleiben erhalten.',
              ),
              items: [
                for (final parent in widget.parents)
                  DropdownMenuItem(
                    value: parent.id,
                    child: Text(
                      '${parent.name} · ${parent.email}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
              onChanged: (value) => setState(() => canPickup = value ?? false),
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
                decoration: const InputDecoration(labelText: 'Beobachtung *'),
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
                  DropdownMenuItem(
                      value: 4, child: Text('4 – Fortgeschritten')),
                  DropdownMenuItem(value: 5, child: Text('5 – Sehr stark')),
                ],
                onChanged: (value) => setState(() => rating = value),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 450) {
                    return DropdownButtonFormField<String>(
                      initialValue: visibility,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Sichtbarkeit'),
                      items: const [
                        DropdownMenuItem(
                          value: 'STAFF_ONLY',
                          child: Text('Nur Trainerteam'),
                        ),
                        DropdownMenuItem(
                          value: 'GUARDIANS_AND_STAFF',
                          child: Text('Mit Eltern teilen'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => visibility = value);
                        }
                      },
                    );
                  }
                  return SegmentedButton<String>(
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
                  );
                },
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

class _DocumentDraft {
  const _DocumentDraft({required this.type, required this.title});

  final String type;
  final String title;
}

class _DocumentDialog extends StatefulWidget {
  const _DocumentDialog();

  @override
  State<_DocumentDialog> createState() => _DocumentDialogState();
}

class _DocumentDialogState extends State<_DocumentDialog> {
  final title = TextEditingController();
  String type = 'PHOTO_CONSENT';

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dokument hinzufügen'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Dokumenttyp'),
              items: const [
                DropdownMenuItem(
                  value: 'PHOTO_CONSENT',
                  child: Text('Fotoeinwilligung'),
                ),
                DropdownMenuItem(
                  value: 'PRIVACY_CONSENT',
                  child: Text('Datenschutzerklärung'),
                ),
                DropdownMenuItem(
                  value: 'PARTICIPATION_PERMISSION',
                  child: Text('Teilnahmeerlaubnis'),
                ),
                DropdownMenuItem(
                  value: 'SWIMMING_PERMISSION',
                  child: Text('Schwimmerlaubnis'),
                ),
                DropdownMenuItem(
                  value: 'DECLARATION',
                  child: Text('Sonstige Erklärung'),
                ),
                DropdownMenuItem(
                  value: 'TEAM_DOCUMENT',
                  child: Text('Mannschaftsdokument'),
                ),
                DropdownMenuItem(
                  value: 'OTHER',
                  child: Text('Sonstiges'),
                ),
              ],
              onChanged: (value) => setState(() => type = value!),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Titel *',
                hintText: 'z. B. Fotoerlaubnis Saison 2026/27',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Erlaubt: PDF, JPEG, PNG oder WebP bis 4 MB. '
              'Die Datei wird privat gespeichert und nur kurzzeitig freigegeben.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (title.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _DocumentDraft(type: type, title: title.text.trim()),
            );
          },
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('Datei auswählen'),
        ),
      ],
    );
  }
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
