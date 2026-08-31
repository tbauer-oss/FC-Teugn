import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/matchday.dart';
import '../../core/providers.dart';

class KitLaundryDutyCard extends ConsumerStatefulWidget {
  const KitLaundryDutyCard({
    required this.matchId,
    required this.staffView,
    this.compact = false,
    this.initialDuty,
    super.key,
  });

  final String matchId;
  final bool staffView;
  final bool compact;
  final KitLaundryDutyModel? initialDuty;

  @override
  ConsumerState<KitLaundryDutyCard> createState() => _KitLaundryDutyCardState();
}

class _KitLaundryDutyCardState extends ConsumerState<KitLaundryDutyCard> {
  KitLaundryDutyModel? _duty;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDuty != null) {
      _duty = widget.initialDuty;
      _loading = false;
    } else {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant KitLaundryDutyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.matchId != widget.matchId) unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final duty = await ref.read(repositoryProvider).kitLaundryDuty(
            widget.matchId,
          );
      if (!mounted) return;
      setState(() {
        _duty = duty;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _message(Object error) {
    if (error is DioException && error.response?.data is Map) {
      return (error.response!.data as Map)['message']?.toString() ??
          'Trikotdienst konnte nicht gespeichert werden.';
    }
    return 'Trikotdienst konnte nicht gespeichert werden.';
  }

  Future<void> _run(
    Future<KitLaundryDutyModel> Function() action,
    String success,
  ) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final duty = await action();
      if (!mounted) return;
      setState(() => _duty = duty);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_message(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseFamily() async {
    final duty = _duty;
    if (duty == null || duty.candidates.isEmpty || _saving) return;
    final selected = await showModalBottomSheet<KitLaundryCandidateModel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trikotdienst festlegen',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 3),
                    Text('Nur Familien nominierter Kinder werden angezeigt.'),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  shrinkWrap: true,
                  itemCount: duty.candidates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final candidate = duty.candidates[index];
                    return ListTile(
                      minTileHeight: 54,
                      leading: Icon(
                        candidate.selected
                            ? Icons.check_circle_rounded
                            : Icons.local_laundry_service_outlined,
                        color: candidate.selected
                            ? const Color(0xFF0F8A5F)
                            : AppColors.yellowDark,
                      ),
                      title: Text(
                        candidate.familyLabel,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: candidate.guardianNames.isEmpty
                          ? null
                          : Text(candidate.guardianNames.join(' · ')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).pop(candidate),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _run(
      () => ref.read(repositoryProvider).assignKitLaundryDuty(
            eventId: widget.matchId,
            playerId: selected.playerId,
          ),
      '${selected.familyLabel} wurde angefragt.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Semantics(
        label: 'Trikotdienst wird geladen',
        child: Container(
          height: widget.compact ? 50 : 62,
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.appColors.outline),
          ),
          child: const Center(child: LinearProgressIndicator()),
        ),
      );
    }
    final duty = _duty;
    if (duty == null || (!widget.staffView && !duty.viewerEligible)) {
      return const SizedBox.shrink();
    }
    final status = switch (duty.status) {
      KitLaundryDutyStatus.proposed => 'Bestätigung offen',
      KitLaundryDutyStatus.confirmed => 'Bestätigt',
      KitLaundryDutyStatus.completed => 'Erledigt',
      _ => duty.nominationPublished ? 'Noch offen' : 'Wartet auf Kader',
    };
    final color = switch (duty.status) {
      KitLaundryDutyStatus.confirmed ||
      KitLaundryDutyStatus.completed =>
        const Color(0xFF0F8A5F),
      KitLaundryDutyStatus.proposed => AppColors.yellowDark,
      _ => const Color(0xFF5E5B52),
    };
    final assignedFamilyLabel = duty.assignedFamilyLabel?.trim();
    final assignedPlayerName = duty.assignedPlayerName?.trim();
    final title = assignedFamilyLabel?.isNotEmpty == true
        ? assignedFamilyLabel!
        : assignedPlayerName?.isNotEmpty == true
            ? 'Familie $assignedPlayerName'
            : duty.nominationPublished
                ? 'Trikotdienst noch nicht vergeben'
                : 'Nach der Kadernominierung automatisch bereit';
    final subtitle = duty.status == KitLaundryDutyStatus.completed
        ? 'Trikots gewaschen – danke!'
        : duty.status == KitLaundryDutyStatus.confirmed
            ? 'Diese Familie übernimmt das Waschen.'
            : duty.status == KitLaundryDutyStatus.proposed
                ? 'Die Familie wurde automatisch angefragt.'
                : duty.nominationPublished
                    ? '${duty.eligibleFamilyCount} Familien in der Rotation'
                    : 'Nur nominierte Familien nehmen an der Rotation teil.';
    return Container(
      key: const ValueKey('kit-laundry-duty-card'),
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 9 : 11,
        vertical: widget.compact ? 7 : 9,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(widget.compact ? 12 : 14),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final veryNarrow = constraints.maxWidth < 350;
          // Keep the descriptive block readable on phones. The action group
          // only moves beside it when a foldable/tablet width is available.
          final inlineActions = constraints.maxWidth >= 640;
          final info = Row(
            children: [
              Container(
                width: widget.compact ? 32 : 36,
                height: widget.compact ? 32 : 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.local_laundry_service_rounded,
                  color: color,
                  size: widget.compact ? 18 : 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Trikotdienst',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: color,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (!widget.compact && !inlineActions)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              if (duty.canRespond) ...[
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => _run(
                            () => ref
                                .read(repositoryProvider)
                                .respondKitLaundryDuty(
                                  eventId: widget.matchId,
                                  accepted: false,
                                ),
                            'Danke, die nächste Familie wird angefragt.',
                          ),
                  style: _compactActionStyle(outlined: true),
                  child: const Text('Ablehnen'),
                ),
                FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _run(
                            () => ref
                                .read(repositoryProvider)
                                .respondKitLaundryDuty(
                                  eventId: widget.matchId,
                                  accepted: true,
                                ),
                            'Trikotdienst bestätigt.',
                          ),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Übernehmen'),
                  style: _compactActionStyle(),
                ),
              ],
              if (duty.canComplete)
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _run(
                            () => ref
                                .read(repositoryProvider)
                                .completeKitLaundryDuty(widget.matchId),
                            'Trikotdienst als erledigt markiert.',
                          ),
                  icon: const Icon(Icons.done_all_rounded),
                  label: const Text('Erledigt'),
                  style: _compactActionStyle(outlined: true),
                ),
              if (duty.canManage && duty.candidates.isNotEmpty)
                TextButton.icon(
                  onPressed: _saving ? null : _chooseFamily,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(
                    duty.assignedPlayerId == null ? 'Festlegen' : 'Ändern',
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          );
          if (!inlineActions && actions.children.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 4),
                Align(
                  alignment:
                      veryNarrow ? Alignment.centerLeft : Alignment.centerRight,
                  child: actions,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              if (actions.children.isNotEmpty) ...[
                const SizedBox(width: 8),
                actions,
              ],
            ],
          );
        },
      ),
    );
  }

  ButtonStyle _compactActionStyle({bool outlined = false}) {
    const minimumSize = Size(0, 40);
    const padding = EdgeInsets.symmetric(horizontal: 8);
    return outlined
        ? OutlinedButton.styleFrom(
            minimumSize: minimumSize,
            padding: padding,
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            iconSize: 17,
          )
        : FilledButton.styleFrom(
            minimumSize: minimumSize,
            padding: padding,
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            iconSize: 17,
          );
  }
}
