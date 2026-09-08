import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/models/event.dart';
import '../../core/models/player.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/responsive_form_dialog.dart';
import '../auth/auth_controller.dart';
import '../talents/match_readiness_card.dart';

final carpoolEventProvider =
    FutureProvider.autoDispose.family<EventModel, String>((ref, id) async {
  ref.watch(authProvider.select((state) => state.user?.id));
  ref.watch(manualDataRefreshProvider);
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(repositoryProvider).event(id);
});

void invalidateCarpoolViews(WidgetRef ref, String eventId) {
  ref.invalidate(carpoolEventProvider(eventId));
  ref.invalidate(matchReadinessProvider(eventId));
  ref.invalidate(eventsProvider);
  ref.invalidate(calendarEventsProvider);
  ref.invalidate(parentDashboardSummaryProvider);
  ref.invalidate(trainerDashboardSummaryProvider);
}

enum CarpoolAction { need, offer }

Future<void> showCarpoolDialog(BuildContext context, String eventId,
        {CarpoolAction? action}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _CarpoolDialog(eventId: eventId, action: action),
    );

/// One compact status and two direct actions on every matchday dashboard.
class CarpoolDashboardCard extends ConsumerWidget {
  const CarpoolDashboardCard(
      {super.key, required this.eventId, this.initialEvent});
  final String eventId;
  final EventModel? initialEvent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(carpoolEventProvider(eventId));
    final event = value.valueOrNull ?? initialEvent;
    final rides = event?.rides;
    final danger = rides?.needsHelp == true;
    final color = danger ? context.appDanger : context.appInfo;
    return Material(
      key: ValueKey('carpool-dashboard-$eventId'),
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => showCarpoolDialog(context, eventId),
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(children: [
                Icon(
                    danger
                        ? Icons.priority_high_rounded
                        : Icons.directions_car_rounded,
                    color: color,
                    size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                  rides == null
                      ? (value.hasError
                          ? 'Mitfahrten erneut laden'
                          : 'Mitfahrten laden …')
                      : '${rides.seatsLabel}${danger ? ' · ${rides.openNeeds} gesucht' : ''}',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: color),
                )),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ]),
            ),
          ),
          if (event?.isCancelled != true &&
              ref.watch(authProvider).user?.role != UserRole.readOnly)
            _RideActions(
              compact: true,
              onNeed: () => showCarpoolDialog(context, eventId,
                  action: CarpoolAction.need),
              onOffer: () => showCarpoolDialog(context, eventId,
                  action: CarpoolAction.offer),
            ),
        ]),
      ),
    );
  }
}

class _CarpoolDialog extends ConsumerStatefulWidget {
  const _CarpoolDialog({required this.eventId, this.action});
  final String eventId;
  final CarpoolAction? action;
  @override
  ConsumerState<_CarpoolDialog> createState() => _CarpoolDialogState();
}

class _CarpoolDialogState extends ConsumerState<_CarpoolDialog> {
  @override
  Widget build(BuildContext context) {
    final asyncEvent = ref.watch(carpoolEventProvider(widget.eventId));
    final event = asyncEvent.valueOrNull;
    return AdaptiveDialogScaffold(
      title: 'Mitfahrten',
      shrinkWrap: true,
      subtitle: event?.fixtureDisplayTitle,
      maxWidth: 640,
      contentPadding: const EdgeInsets.all(12),
      content: event != null
          ? CarpoolSection(
              event: event,
              players: ref.watch(playersProvider).valueOrNull ?? const [],
              initialAction: widget.action,
              onRefresh: () async {
                invalidateCarpoolViews(ref, widget.eventId);
                await ref.read(carpoolEventProvider(widget.eventId).future);
              },
            )
          : asyncEvent.hasError
              ? Column(children: [
                  const Text('Die Mitfahrten konnten nicht geladen werden.'),
                  TextButton.icon(
                      onPressed: () =>
                          ref.invalidate(carpoolEventProvider(widget.eventId)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Erneut laden')),
                ])
              : const LinearProgressIndicator(),
      actions: const [],
    );
  }
}

class CarpoolSection extends ConsumerStatefulWidget {
  const CarpoolSection(
      {super.key,
      required this.event,
      required this.players,
      required this.onRefresh,
      this.initialAction});
  final EventModel event;
  final List<PlayerModel> players;
  final Future<void> Function() onRefresh;
  final CarpoolAction? initialAction;
  @override
  ConsumerState<CarpoolSection> createState() => _CarpoolSectionState();
}

class _CarpoolSectionState extends ConsumerState<CarpoolSection> {
  bool _busy = false;
  bool _started = false;
  EventModel get event => widget.event;
  String? get userId => ref.read(authProvider).user?.id;
  bool get canBook =>
      ref.read(authProvider).user?.role != UserRole.readOnly &&
      !event.isCancelled &&
      (event.capabilities.canOfferRide || event.capabilities.canRespond);
  List<PlayerModel> get players => widget.players
      .where((p) =>
          p.status == PlayerStatus.active &&
          (p.teamId == event.teamId ||
              event.targetTeams.any((t) => t.id == p.teamId)))
      .toList();

  @override
  Widget build(BuildContext context) {
    if (!_started && widget.initialAction != null && canBook) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.initialAction == CarpoolAction.offer
              ? _offerRide()
              : _selectPeople();
        }
      });
    }
    final rides = event.rides;
    final open = event.carpoolNeeds
        .where((n) => n.status == CarpoolNeedStatus.open)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Fahrgemeinschaften',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            _RideBadge(
                label: rides.seatsLabel,
                color: rides.freeSeats > 0
                    ? context.appSuccess
                    : context.appColors.textMuted),
            if (rides.needsHelp)
              _RideBadge(
                  label: '${rides.openNeeds} gesucht',
                  color: context.appDanger),
          ]),
      const SizedBox(height: 6),
      _RideActions(
          onNeed: canBook && !_busy ? () => _selectPeople() : null,
          onOffer:
              event.capabilities.canOfferRide && !event.isCancelled && !_busy
                  ? _offerRide
                  : null),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      if (open.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: context.appDanger.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                rides.freeSeats == 0
                    ? 'Noch kein Platz verfügbar'
                    : 'Passende Mitfahrt gesucht',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: context.appDanger)),
            for (final need in open)
              Row(children: [
                Icon(Icons.front_hand_outlined,
                    size: 16, color: context.appDanger),
                const SizedBox(width: 7),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(need.playerName,
                            style: const TextStyle(fontSize: 13)))),
                if (need.canCancel)
                  IconButton(
                      tooltip: 'Bedarf zurückziehen',
                      onPressed: _busy
                          ? null
                          : () => _run(() => ref
                              .read(repositoryProvider)
                              .deleteCarpoolNeed(
                                  eventId: event.id, needId: need.id)),
                      icon: const Icon(Icons.close_rounded, size: 19)),
              ]),
          ]),
        ),
      ],
      const SizedBox(height: 8),
      if (event.carpoolOffers.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Noch keine Fahrt angeboten.',
                style: TextStyle(
                    fontSize: 13, color: context.appColors.textMuted))),
      for (final offer in event.carpoolOffers) ...[
        _offerCard(offer),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _offerCard(CarpoolOffer offer) {
    final active = offer.passengers
        .where((p) =>
            p.status == CarpoolRequestStatus.confirmed ||
            p.status == CarpoolRequestStatus.requested)
        .toList();
    final time =
        '${offer.departureAt.hour.toString().padLeft(2, '0')}:${offer.departureAt.minute.toString().padLeft(2, '0')}';
    final anotherDay = DateUtils.dateOnly(offer.departureAt) !=
        DateUtils.dateOnly(event.startAt);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 7),
      decoration: BoxDecoration(
          color: context.appColors.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.appColors.outline)),
      child: Material(
        type: MaterialType.transparency,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.directions_car_rounded,
                color: context.appInfo, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(offer.driverName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800))),
            const SizedBox(width: 4),
            _RideBadge(
                label: offer.freeSeats > 0 ? '${offer.freeSeats} frei' : 'Voll',
                color: offer.freeSeats > 0
                    ? context.appSuccess
                    : context.appColors.textMuted),
            if (offer.canManage)
              PopupMenuButton<String>(
                tooltip: 'Fahrt verwalten',
                onSelected: (_) => _deleteOffer(offer),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'delete', child: Text('Fahrt zurückziehen'))
                ],
              ),
          ]),
          const SizedBox(height: 3),
          Text(
              '${anotherDay ? '${offer.departureAt.day}.${offer.departureAt.month}. · ' : ''}$time Uhr · ${offer.departureLocation}',
              style:
                  TextStyle(fontSize: 13, color: context.appColors.textMuted)),
          if (offer.notes?.isNotEmpty == true ||
              offer.driverPhone?.isNotEmpty == true)
            ExpansionTile(
              key: PageStorageKey('ride-details-${offer.id}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              dense: true,
              visualDensity: VisualDensity.compact,
              title: const Text('Kontakt & Hinweise',
                  style: TextStyle(fontSize: 12)),
              children: [
                if (offer.notes?.isNotEmpty == true)
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(offer.notes!,
                          style: const TextStyle(fontSize: 13))),
                if (offer.driverPhone?.isNotEmpty == true)
                  Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => launchUrl(
                            Uri(scheme: 'tel', path: offer.driverPhone!)),
                        icon: const Icon(Icons.call_outlined, size: 18),
                        label: Text(offer.driverPhone!),
                      )),
              ],
            ),
          for (final passenger in active)
            Row(children: [
              Icon(
                  passenger.status == CarpoolRequestStatus.confirmed
                      ? Icons.check_circle_outline
                      : Icons.schedule,
                  size: 16,
                  color: context.appSuccess),
              const SizedBox(width: 6),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                          '${passenger.playerName} · ${passenger.status == CarpoolRequestStatus.confirmed ? 'gebucht' : 'angefragt'}',
                          style: const TextStyle(fontSize: 12)))),
              if (offer.canManage &&
                  passenger.status == CarpoolRequestStatus.requested)
                IconButton(
                    tooltip: 'Platz bestätigen',
                    onPressed: _busy
                        ? null
                        : () => _updatePassenger(
                            offer, passenger, CarpoolRequestStatus.confirmed),
                    icon: const Icon(Icons.check_rounded, size: 20)),
              if (passenger.canCancel || offer.canManage)
                IconButton(
                    tooltip: 'Buchung stornieren',
                    onPressed: _busy
                        ? null
                        : () => _updatePassenger(
                            offer, passenger, CarpoolRequestStatus.cancelled),
                    icon: const Icon(Icons.close_rounded, size: 18)),
            ]),
          if (canBook && offer.freeSeats > 0)
            Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _selectPeople(offer: offer),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Hier eintragen'),
                )),
        ]),
      ),
    );
  }

  Future<void> _refresh() async {
    invalidateCarpoolViews(ref, event.id);
    await widget.onRefresh();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_rideError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectPeople({CarpoolOffer? offer}) async {
    // A fast tap must not open a permanently empty child selection while loading.
    var availablePlayers = players;
    if (availablePlayers.isEmpty) {
      setState(() => _busy = true);
      try {
        final loaded = await ref.read(playersProvider.future);
        availablePlayers = loaded
            .where((p) =>
                p.status == PlayerStatus.active &&
                (p.teamId == event.teamId ||
                    event.targetTeams.any((t) => t.id == p.teamId)))
            .toList();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_rideError(error))));
        }
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (!mounted) return;
    }
    final booked = event.carpoolOffers
        .expand((o) => o.passengers)
        .where((p) => p.status == CarpoolRequestStatus.confirmed)
        .map((p) => p.personKey)
        .toSet();
    await showDialog<void>(
        context: context,
        builder: (_) => _RidePeopleDialog(
              players: availablePlayers
                  .where((p) => !booked.contains('child:${p.id}'))
                  .toList(),
              allowSelf:
                  offer?.driverId != userId && !booked.contains('user:$userId'),
              maxSeats: offer?.freeSeats ?? 8,
              offer: offer,
              onSubmit: (ids, includeSelf, note) async {
                if (offer == null) {
                  await ref.read(repositoryProvider).createCarpoolNeeds(
                      eventId: event.id,
                      playerIds: ids,
                      includeSelf: includeSelf,
                      note: note);
                } else {
                  await ref.read(repositoryProvider).bookCarpoolSeats(
                      eventId: event.id,
                      offerId: offer.id,
                      playerIds: ids,
                      includeSelf: includeSelf);
                }
                await _refresh();
              },
            ));
  }

  Future<void> _offerRide() => showDialog<void>(
      context: context,
      builder: (_) => _RideOfferDialog(
          event: event,
          onSubmit: (seats, location, departure, note) async {
            await ref.read(repositoryProvider).createCarpoolOffer(
                eventId: event.id,
                seatsTotal: seats,
                departureLocation: location,
                departureAt: departure,
                notes: note);
            await _refresh();
          }));

  Future<void> _updatePassenger(CarpoolOffer offer, CarpoolPassenger passenger,
          CarpoolRequestStatus status) =>
      _run(() => ref.read(repositoryProvider).updateCarpoolPassenger(
          eventId: event.id,
          offerId: offer.id,
          passengerId: passenger.id,
          status: status));

  Future<void> _deleteOffer(CarpoolOffer offer) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('Fahrt zurückziehen?'),
              content: const Text(
                  'Gebuchte Mitfahrer erhalten wieder offenen Bedarf. Freie Plätze in anderen Fahrten werden automatisch zugeordnet.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Behalten')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Zurückziehen'))
              ],
            ));
    if (confirmed == true && mounted) {
      await _run(() => ref
          .read(repositoryProvider)
          .deleteCarpoolOffer(eventId: event.id, offerId: offer.id));
    }
  }
}

class _RideBadge extends StatelessWidget {
  const _RideBadge({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(8)),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      );
}

class _RideActions extends StatelessWidget {
  const _RideActions(
      {required this.onNeed, required this.onOffer, this.compact = false});
  final VoidCallback? onNeed;
  final VoidCallback? onOffer;
  final bool compact;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 280 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.35;
        final width =
            twoColumns ? (constraints.maxWidth - 6) / 2 : constraints.maxWidth;
        final style = TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            textStyle: const TextStyle(
                fontFamily: 'Arial',
                fontSize: 13,
                fontWeight: FontWeight.w800));
        return Wrap(spacing: 6, runSpacing: 2, children: [
          SizedBox(
              width: width,
              child: TextButton.icon(
                  onPressed: onNeed,
                  style: style,
                  icon: const Icon(Icons.airline_seat_recline_normal_rounded,
                      size: 18),
                  label: Text(compact ? 'Mitfahren' : 'Mitfahrt suchen'))),
          SizedBox(
              width: width,
              child: TextButton.icon(
                  onPressed: onOffer,
                  style: style,
                  icon: const Icon(Icons.add_road_rounded, size: 18),
                  label: Text(compact ? 'Anbieten' : 'Plätze anbieten'))),
        ]);
      });
}

class _RidePeopleDialog extends StatefulWidget {
  const _RidePeopleDialog(
      {required this.players,
      required this.allowSelf,
      required this.maxSeats,
      required this.onSubmit,
      this.offer});
  final List<PlayerModel> players;
  final bool allowSelf;
  final int maxSeats;
  final CarpoolOffer? offer;
  final Future<void> Function(List<String>, bool, String?) onSubmit;
  @override
  State<_RidePeopleDialog> createState() => _RidePeopleDialogState();
}

class _RidePeopleDialogState extends State<_RidePeopleDialog> {
  final Set<String> _selected = {};
  final _note = TextEditingController();
  bool _self = false;
  bool _saving = false;
  String? _error;
  int get count => _selected.length + (_self ? 1 : 0);
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResponsiveFormDialog(
        shrinkWrap: true,
        title: widget.offer == null ? 'Wer fährt mit?' : 'Plätze direkt buchen',
        subtitle: widget.offer == null
            ? 'Freie Plätze werden automatisch zugeordnet. Gemeinsam ausgewählte Personen fahren zusammen.'
            : '${widget.offer!.driverName} · ${widget.maxSeats} ${widget.maxSeats == 1 ? 'Platz frei' : 'Plätze frei'}',
        saving: _saving,
        saveLabel: widget.offer == null
            ? 'Mitfahrt eintragen'
            : '$count ${count == 1 ? 'Platz buchen' : 'Plätze buchen'}',
        saveIcon: Icons.check_rounded,
        preferInlineActions: true,
        onSave: count == 0 ? null : _save,
        children: [
          if (widget.allowSelf)
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ich selbst'),
                secondary: const Icon(Icons.person_outline),
                value: _self,
                onChanged: _saving || (!_self && count >= widget.maxSeats)
                    ? null
                    : (value) => setState(() => _self = value == true)),
          for (final player in widget.players)
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(player.displayName),
                value: _selected.contains(player.id),
                onChanged: _saving ||
                        (!_selected.contains(player.id) &&
                            count >= widget.maxSeats)
                    ? null
                    : (value) => setState(() {
                          if (value == true) {
                            _selected.add(player.id);
                          } else {
                            _selected.remove(player.id);
                          }
                        })),
          if (!widget.allowSelf && widget.players.isEmpty)
            const Text(
                'Alle verfügbaren Personen sind bereits als Mitfahrer eingetragen.'),
          if (widget.offer == null)
            TextField(
                controller: _note,
                enabled: !_saving,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Hinweis (optional)')),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child:
                    Text(_error!, style: TextStyle(color: context.appDanger))),
        ],
      );
  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_selected.toList(), _self,
          _note.text.trim().isEmpty ? null : _note.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = _rideError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _RideOfferDialog extends StatefulWidget {
  const _RideOfferDialog({required this.event, required this.onSubmit});
  final EventModel event;
  final Future<void> Function(int, String, DateTime, String?) onSubmit;
  @override
  State<_RideOfferDialog> createState() => _RideOfferDialogState();
}

class _RideOfferDialogState extends State<_RideOfferDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _location;
  final _note = TextEditingController();
  late DateTime _departure;
  int _seats = 2;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _location = TextEditingController(text: widget.event.meetingLocation ?? '');
    _departure = widget.event.meetingAt ??
        widget.event.startAt.subtract(const Duration(minutes: 30));
  }

  @override
  void dispose() {
    _location.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResponsiveFormDialog(
        title: 'Plätze anbieten',
        subtitle:
            'Offener Bedarf wird passenden freien Plätzen direkt zugeordnet.',
        saveLabel: 'Fahrt anbieten',
        saveIcon: Icons.directions_car_rounded,
        saving: _saving,
        onSave: _save,
        preferInlineActions: true,
        children: [
          Form(
              key: _form,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                        isExpanded: true,
                        itemHeight: null,
                        initialValue: _seats,
                        decoration: const InputDecoration(
                            labelText: 'Freie Plätze (ohne Fahrer)'),
                        items: [
                          for (var i = 1; i <= 8; i++)
                            DropdownMenuItem(
                                value: i,
                                child:
                                    Text('$i ${i == 1 ? 'Platz' : 'Plätze'}'))
                        ],
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _seats = v!)),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _location,
                        enabled: !_saving,
                        maxLength: 160,
                        decoration:
                            const InputDecoration(labelText: 'Abfahrtsort'),
                        validator: (v) => v?.trim().isNotEmpty == true
                            ? null
                            : 'Bitte Abfahrtsort eingeben.'),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_rounded),
                        title: const Text('Abfahrt'),
                        subtitle: Text(
                            '${_departure.day}.${_departure.month}. · ${TimeOfDay.fromDateTime(_departure).format(context)} Uhr'),
                        trailing: const Icon(Icons.edit_outlined, size: 18),
                        onTap: _saving ? null : _pickDeparture),
                    TextField(
                        controller: _note,
                        enabled: !_saving,
                        maxLength: 500,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            labelText: 'Hinweis (optional)')),
                    if (_error != null)
                      Text(_error!, style: TextStyle(color: context.appDanger)),
                  ]))
        ],
      );
  Future<void> _pickDeparture() async {
    final day = await showDatePicker(
        context: context,
        initialDate: _departure,
        firstDate: widget.event.startAt.subtract(const Duration(days: 7)),
        lastDate: widget.event.startAt);
    if (day == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_departure));
    if (time != null && mounted) {
      setState(() => _departure =
          DateTime(day.year, day.month, day.day, time.hour, time.minute));
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_departure.isAfter(widget.event.startAt)) {
      setState(() => _error = 'Die Abfahrt muss vor dem Terminbeginn liegen.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_seats, _location.text.trim(), _departure,
          _note.text.trim().isEmpty ? null : _note.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = _rideError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _rideError(Object error) {
  if (error is DioException && error.response?.data is Map) {
    final message = (error.response!.data as Map)['message'];
    if (message is String && message.isNotEmpty) return message;
  }
  return 'Speichern nicht bestätigt. Bitte Verbindung prüfen und erneut versuchen.';
}
