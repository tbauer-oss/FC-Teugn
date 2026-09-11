import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../core/google_maps_navigation.dart';
import '../../core/models/event.dart';
import '../../core/models/personal_response.dart';
import '../../core/providers.dart';
import '../shared/family_responses.dart';
import '../shared/response_deadline.dart';
import 'parent_home_models.dart';

const parentTrainingColor = Color(0xFF079B57);
const parentMatchColor = Color(0xFF087CF0);

class ParentPageFrame extends StatelessWidget {
  const ParentPageFrame(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
        color: context.appColors.surface,
        textStyle: Theme.of(context)
            .textTheme
            .bodyMedium!
            .copyWith(color: context.appColors.text),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontFamily: 'Arial',
                            fontSize: 29,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            color: context.appColors.text)),
                    const SizedBox(height: 6),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color: context.appColors.textMuted)),
                    const SizedBox(height: 18),
                    ...children,
                  ]),
            ),
          )),
        ),
      );
}

class ParentLinkRow extends StatelessWidget {
  const ParentLinkRow(
      {super.key,
      required this.icon,
      required this.title,
      required this.onTap,
      this.attention = false,
      this.subtitle,
      this.iconColor,
      this.iconSize = 22});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool attention;
  final Color? iconColor;
  final double iconSize;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          textStyle: Theme.of(context)
              .textTheme
              .bodyMedium!
              .copyWith(color: context.appColors.text),
          color: context.isDarkMode
              ? context.appColors.surfaceRaised
              : const Color(0xFFF7F8FA),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
              side: BorderSide(
                  color: context.appColors.outline.withValues(alpha: .55))),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(children: [
                Icon(icon, size: iconSize, color: iconColor),
                const SizedBox(width: 10),
                if (attention) ...[
                  const Icon(Icons.circle, size: 9, color: Color(0xFFFFA000)),
                  const SizedBox(width: 7)
                ],
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: TextStyle(
                                fontSize: 13,
                                color: context.appColors.textMuted)),
                    ])),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right,
                    size: 20, color: context.appColors.textMuted),
              ]),
            ),
          ),
        ),
      );
}

void openParentVisit(BuildContext context, ParentVisit visit) {
  if (visit.item.isMatch) {
    final tournament = visit.item.event?.category.isTournament == true ||
        (visit.response?.category.contains('TOURNAMENT') ?? false) ||
        visit.response?.category == 'FOOTBALL_FESTIVAL';
    context.go(Uri(
            path: '/parent/matches/${visit.item.eventId}',
            queryParameters: tournament ? {'planning': 'tournament'} : null)
        .toString());
  } else if (visit.item.event == null && visit.response != null) {
    context.go(Uri(path: '/parent/responses', queryParameters: {
      'eventId': visit.item.eventId,
      'playerId': visit.player.id
    }).toString());
  } else {
    context.go(Uri(path: '/parent/events', queryParameters: {
      'eventId': visit.item.eventId,
      'date': visit.item.startAt.toIso8601String()
    }).toString());
  }
}

Future<void> showParentAnswer(BuildContext context, ParentVisit visit) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 580),
      builder: (sheetContext) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, 24 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${visit.player.displayName} · ${visit.title}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                  '${parentDate(visit.item.startAt)} · ${parentClock(visit.item.startAt)} Uhr'),
              const SizedBox(height: 16),
              if (visit.response != null) ...[
                ResponseDeadlineNotice(
                    deadline: visit.response!.responseDeadline),
                const SizedBox(height: 8),
                if (visit.response!.canRespond)
                  PersonalResponseQuickActions(
                      item: visit.response!,
                      expanded: true,
                      comfortable: true,
                      onSaved: () {
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      })
                else
                  const Text('Änderungen bitte mit dem Trainerteam abstimmen.'),
              ],
              TextButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    context.go('/parent/messages?section=contact');
                  },
                  child: const Text('Trainer kontaktieren')),
              TextButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    context.go(Uri(path: '/parent/responses', queryParameters: {
                      'eventId': visit.item.eventId,
                      'playerId': visit.player.id
                    }).toString());
                  },
                  child: Text(visit.response?.isRegularTraining == true
                      ? 'Mehrere Trainings zusagen'
                      : 'Alle Rückmeldungen dieses Kindes')),
            ]),
      ),
    );

class ParentResponseStatus extends StatelessWidget {
  const ParentResponseStatus({super.key, required this.response});
  final PersonalResponseModel? response;
  @override
  Widget build(BuildContext context) {
    final status = response?.responseStatus;
    final yes = status == AttendanceStatus.yes;
    final no = status == AttendanceStatus.no;
    final color = yes
        ? parentTrainingColor
        : no
            ? context.appDanger
            : const Color(0xFFB77700);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(
          yes
              ? Icons.check_circle
              : no
                  ? Icons.cancel
                  : Icons.circle,
          size: yes || no ? 17 : 10,
          color: color),
      const SizedBox(width: 6),
      Flexible(
          child: Text(
              yes
                  ? 'Zugesagt'
                  : no
                      ? 'Abgesagt'
                      : response == null
                          ? 'Details & Rückmeldung'
                          : 'Rückmeldung offen',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: yes || no ? color : context.appColors.text))),
    ]);
  }
}

class ParentRouteLink extends ConsumerWidget {
  const ParentRouteLink({super.key, required this.event});
  final EventModel event;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (event.fixtureIsHome != false) return const SizedBox.shrink();
    final address = resolvedMatchNavigationAddress(
        isAway: true, address: event.address, location: event.location);
    if (address == null) return const SizedBox.shrink();
    final estimate =
        ref.watch(matchRouteEstimateProvider(event.id)).valueOrNull;
    final km = estimate?.distanceKm;
    final distance = km == null
        ? null
        : (km == km.roundToDouble()
            ? km.toInt().toString()
            : km.toStringAsFixed(1).replaceAll('.', ','));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        key: ValueKey('parent-route-${event.id}'),
        onTap: () => openAddressInGoogleMaps(context, address),
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.location_on, size: 21, color: parentMatchColor),
              const SizedBox(width: 5),
              Flexible(
                  child: Text(
                      distance == null
                          ? 'Route ab Teugn öffnen'
                          : 'Route · ca. $distance km ab Teugn',
                      style: const TextStyle(
                          color: parentMatchColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600))),
            ])),
      ),
      if (estimate != null)
        Text(estimate.attribution,
            style: TextStyle(fontSize: 11, color: context.appColors.textMuted)),
    ]);
  }
}

class ParentEventCard extends StatelessWidget {
  const ParentEventCard({super.key, required this.visits});
  final List<ParentVisit> visits;
  @override
  Widget build(BuildContext context) {
    final first = visits.first;
    final match = first.item.isMatch;
    final color = match ? parentMatchColor : parentTrainingColor;
    return Container(
      key: ValueKey(
          'parent-${match ? 'match' : 'training'}-card-${first.item.eventId}'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: context.appColors.outline.withValues(alpha: .55)),
          boxShadow: [
            BoxShadow(
                color: Colors.black
                    .withValues(alpha: context.isDarkMode ? 0 : .035),
                blurRadius: 12,
                offset: const Offset(0, 3))
          ]),
      child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 4, child: ColoredBox(color: color)),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                          onTap: () => openParentVisit(context, first),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Icon(
                                        match
                                            ? Icons.sports_soccer
                                            : Icons.sports,
                                        size: 30,
                                        color: color)),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(
                                          '${match ? 'NÄCHSTES SPIEL' : 'TRAINING'} · ${visits.length == 1 ? first.childLabel : '${visits.length} Kinder'}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              letterSpacing: .2,
                                              color:
                                                  context.appColors.textMuted)),
                                      const SizedBox(height: 4),
                                      Text(
                                          match
                                              ? first.title
                                              : parentDate(first.item.startAt),
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              height: 1.3)),
                                      const SizedBox(height: 3),
                                      Text(
                                          match
                                              ? parentDate(first.item.startAt)
                                              : '${parentClock(first.item.startAt)} Uhr · ${first.item.location}',
                                          style: TextStyle(
                                              fontSize: 14,
                                              height: 1.4,
                                              color:
                                                  context.appColors.textMuted)),
                                    ])),
                              ])),
                      if (match) ...[
                        const SizedBox(height: 12),
                        Padding(
                            padding: const EdgeInsets.only(left: 40),
                            child: Wrap(spacing: 28, runSpacing: 8, children: [
                              _TimeColumn(
                                  label: 'Treffpunkt',
                                  value: first.meetingAt == null
                                      ? 'Noch offen'
                                      : parentClock(first.meetingAt!)),
                              _TimeColumn(
                                  label: 'Beginn',
                                  value: parentClock(first.item.startAt)),
                            ])),
                      ],
                      for (final visit in visits) ...[
                        if (visits.length > 1) ...[
                          const SizedBox(height: 10),
                          Text(visit.childLabel,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700))
                        ],
                        const SizedBox(height: 8),
                        _VisitAnswer(visit: visit),
                      ],
                      if (match && first.item.event != null)
                        Padding(
                            padding: const EdgeInsets.only(left: 36),
                            child: ParentRouteLink(event: first.item.event!)),
                      if (match) ...[
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                            onPressed: () => openParentVisit(context, first),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                backgroundColor: context.isDarkMode
                                    ? context.appColors.surfaceRaised
                                    : const Color(0xFFF3F4F6),
                                foregroundColor: context.appColors.text,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(7))),
                            child: const Row(children: [
                              Expanded(
                                  child: Text('Kader & Spielinfo',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600))),
                              Icon(Icons.chevron_right, size: 19)
                            ])),
                      ],
                    ]))),
      ])),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Semantics(
      label: '$label $value',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: context.appColors.textMuted)),
        Text(value,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      ]));
}

class _VisitAnswer extends StatelessWidget {
  const _VisitAnswer({required this.visit});
  final ParentVisit visit;
  @override
  Widget build(BuildContext context) => ResponseDeadlineGate(
      deadline: visit.response?.responseDeadline,
      builder: (context, closed) {
        final response = visit.response;
        final canRespond = response?.canRespond == true && !closed;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                  padding: EdgeInsets.only(left: visit.item.isMatch ? 40 : 40),
                  child: Row(children: [
                    Expanded(child: ParentResponseStatus(response: response)),
                    if (canRespond && !response!.isOpen)
                      TextButton(
                          onPressed: () => showParentAnswer(context, visit),
                          child: const Text('Ändern',
                              style: TextStyle(fontSize: 13))),
                  ])),
              if (response != null && response.responseDeadline != null)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        closed
                            ? 'Frist abgelaufen · Änderungen nur durch Trainer'
                            : 'Antwort bis ${parentDate(response.responseDeadline!, short: true)} ${parentClock(response.responseDeadline!)}',
                        style: TextStyle(
                            fontSize: 12, color: context.appColors.textMuted))),
              if (canRespond && response!.isOpen) ...[
                const SizedBox(height: 10),
                PersonalResponseQuickActions(
                    key: ValueKey('parent-answer-${visit.key}'),
                    item: response,
                    expanded: true,
                    comfortable: true),
              ] else if (closed ||
                  (response != null && !response.canRespond && response.isOpen))
                TextButton(
                    onPressed: () =>
                        context.go('/parent/messages?section=contact'),
                    child: const Text('Trainer kontaktieren')),
            ]);
      });
}

class ParentFamilyEventRow extends StatelessWidget {
  const ParentFamilyEventRow({super.key, required this.visit});
  final ParentVisit visit;
  @override
  Widget build(BuildContext context) {
    final match = visit.item.isMatch;
    final color = match ? parentMatchColor : parentTrainingColor;
    return ResponseDeadlineGate(
        deadline: visit.response?.responseDeadline,
        builder: (context, closed) {
          final answer = visit.response?.isOpen == true &&
              visit.response?.canRespond == true &&
              !closed;
          Widget button() => FilledButton(
              onPressed: () => showParentAnswer(context, visit),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7))),
              child: const Text('Antworten',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)));
          return ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Container(
                key: ValueKey('family-event-${visit.key}'),
                decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(color: color, width: 4),
                        bottom: BorderSide(
                            color: context.appColors.outline
                                .withValues(alpha: .5)))),
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final inlineAnswer = !match &&
                          answer &&
                          constraints.maxWidth >= 300 &&
                          MediaQuery.textScalerOf(context).scale(1) < 1.3;
                      return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(match ? Icons.sports_soccer : Icons.sports,
                                color: color, size: 29),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  InkWell(
                                      onTap: () =>
                                          openParentVisit(context, visit),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                match
                                                    ? visit.title
                                                    : 'Training',
                                                style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                    height: 1.3,
                                                    color: context
                                                        .appColors.text)),
                                            Text(
                                                '${parentDate(visit.item.startAt, short: true)} · ${match ? 'Beginn ' : ''}${parentClock(visit.item.startAt)}',
                                                style: const TextStyle(
                                                    fontSize: 13, height: 1.5)),
                                            if (!match && answer)
                                              Text(visit.item.location,
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color: context.appColors
                                                          .textMuted)),
                                          ])),
                                  if (match)
                                    Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                              'Treffpunkt ${visit.meetingAt == null ? 'noch offen' : parentClock(visit.meetingAt!)}',
                                              style: const TextStyle(
                                                  fontSize: 13, height: 1.5)),
                                          if (!answer)
                                            ParentResponseStatus(
                                                response: visit.response),
                                        ])
                                  else if (!answer)
                                    ParentResponseStatus(
                                        response: visit.response),
                                  if (answer && !inlineAnswer)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: button()),
                                  if (closed)
                                    TextButton(
                                        onPressed: () => context.go(
                                            '/parent/messages?section=contact'),
                                        child: const Text(
                                            'Frist abgelaufen · Trainer kontaktieren',
                                            style: TextStyle(fontSize: 12))),
                                  if (match && visit.item.event != null)
                                    ParentRouteLink(event: visit.item.event!),
                                ])),
                            if (inlineAnswer) ...[
                              const SizedBox(width: 8),
                              button()
                            ],
                            IconButton(
                                onPressed: () =>
                                    openParentVisit(context, visit),
                                tooltip: '${visit.title} öffnen',
                                constraints: const BoxConstraints(
                                    minWidth: 40, minHeight: 44),
                                padding: const EdgeInsets.all(8),
                                icon:
                                    const Icon(Icons.chevron_right, size: 20)),
                          ]);
                    })),
              ));
        });
  }
}
