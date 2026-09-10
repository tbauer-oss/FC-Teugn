import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/models/matchday.dart';
import '../../core/widgets/adaptive_layout.dart';

/// One responsive surface for the match tab and its focused fullscreen view.
/// It only reports user intent; nomination, persistence and sharing stay in the
/// match controller. In particular, rendering never changes stored positions.
class ModernLineupView extends StatelessWidget {
  const ModernLineupView(
      {super.key,
      required this.positions,
      required this.bench,
      required this.formation,
      required this.formations,
      required this.strength,
      required this.editable,
      required this.saving,
      required this.shared,
      required this.onFormation,
      required this.onAutomatic,
      required this.onTactics,
      required this.onFullscreen,
      required this.onSave,
      required this.onShare,
      required this.onMove,
      required this.onMoveEnd,
      required this.onEdit,
      required this.onBench,
      this.notice,
      this.fullscreen = false});
  final List<LineupPositionModel> positions;
  final List<MatchPlayer> bench;
  final String formation, strength;
  final List<String> formations;
  final bool editable, saving, shared;
  final bool fullscreen;
  final ValueChanged<String> onFormation;
  final VoidCallback onAutomatic,
      onTactics,
      onFullscreen,
      onSave,
      onShare,
      onMoveEnd;
  final void Function(int index, Offset position) onMove;
  final ValueChanged<int> onEdit;
  final ValueChanged<MatchPlayer> onBench;
  final Widget? notice;

  ButtonStyle _style() => OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      );

  Widget _formation(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: context.appColors.surfaceRaised,
            border: Border.all(color: context.appColors.outline),
            borderRadius: BorderRadius.circular(11)),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
          key: const ValueKey('modern-lineup-formation'),
          value: formation,
          isExpanded: true,
          itemHeight: null,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.expand_more_rounded),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700),
          items: formations
              .map((value) => DropdownMenuItem(
                  value: value,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(value))))
              .toList(),
          onChanged: saving
              ? null
              : (value) {
                  if (value != null) onFormation(value);
                },
        )),
      );

  Widget _tools(BuildContext context, bool sidebar) =>
      LayoutBuilder(builder: (context, constraints) {
        final scaled = MediaQuery.textScalerOf(context).scale(14) > 19;
        final formationWidth = sidebar || scaled
            ? constraints.maxWidth
            : math.min(144.0, constraints.maxWidth * .4);
        return Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: formationWidth, child: _formation(context)),
              Tooltip(
                  message: 'Nach Positionen aufstellen',
                  child: OutlinedButton(
                    key: const ValueKey('lineup-automatic'),
                    style: _style(),
                    onPressed: saving ? null : onAutomatic,
                    child: const Icon(Icons.auto_awesome_outlined, size: 21),
                  )),
              OutlinedButton.icon(
                  key: const ValueKey('open-tactics-board'),
                  style: _style(),
                  onPressed: saving ? null : onTactics,
                  icon: const Icon(Icons.gesture_rounded, size: 19),
                  label: const Text('Taktikboard')),
            ]);
      });

  Widget _summary(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Wrap(
            spacing: 14,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text('${positions.length} auf dem Feld · $strength',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              Text(
                  saving
                      ? 'Speichert …'
                      : shared
                          ? 'Intern geteilt'
                          : 'Entwurf',
                  style: TextStyle(
                      color: context.appColors.textMuted, fontSize: 13)),
            ]),
      );

  Widget _bank(BuildContext context, bool sidebar) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Row(children: [
              const Icon(Icons.event_seat_outlined, size: 19),
              const SizedBox(width: 7),
              Expanded(
                  child: Text('Ersatzbank · ${bench.length}',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
            ])),
        if (bench.isEmpty)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Keine Ersatzspieler',
                  style: TextStyle(color: context.appColors.textMuted))),
        LayoutBuilder(builder: (context, constraints) {
          final twoColumns = !sidebar &&
              constraints.maxWidth >= 340 &&
              MediaQuery.textScalerOf(context).scale(14) <= 18;
          final tileWidth = twoColumns
              ? (constraints.maxWidth - 8) / 2
              : constraints.maxWidth;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final player in bench)
              SizedBox(
                  width: tileWidth,
                  child: Material(
                    color: context.appColors.surfaceRaised,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                        side: BorderSide(color: context.appColors.outline)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: editable && !saving ? () => onBench(player) : null,
                      child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(children: [
                            JerseyIcon(
                                number: player.shirtNumber?.toString() ?? '–',
                                size: 38),
                            const SizedBox(width: 9),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(player.name,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  Text(player.position ?? 'FLEX',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: context.appColors.textMuted)),
                                ])),
                            if (editable)
                              const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child:
                                      Icon(Icons.swap_horiz_rounded, size: 18)),
                          ])),
                    ),
                  )),
          ]);
        }),
      ]);

  Widget _hint(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline,
              size: 16, color: context.appColors.textMuted),
          const SizedBox(width: 7),
          Expanded(
              child: Text(
                  editable
                      ? 'Ziehen zum Verschieben · Tippen zum Bearbeiten'
                      : 'Tippen für den vollständigen Spielernamen',
                  style: TextStyle(
                      fontSize: 12, color: context.appColors.textMuted))),
        ]),
      );

  Widget _actions(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final stacked = constraints.maxWidth < 350 ||
            MediaQuery.textScalerOf(context).scale(14) > 19;
        final buttons = [
          OutlinedButton.icon(
              key: const ValueKey('lineup-save-action'),
              onPressed: saving ? null : onSave,
              style: _style(),
              icon: const Icon(Icons.save_outlined, size: 20),
              label: const Text('Speichern')),
          FilledButton.icon(
              key: const ValueKey('lineup-publish-action'),
              onPressed: saving ? null : onShare,
              style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11))),
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              label: const Text('Intern teilen',
                  semanticsLabel:
                      'Aufstellung intern mit dem Trainerteam teilen')),
        ];
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(height: 16),
              if (stacked) ...[
                buttons[0],
                const SizedBox(height: 6),
                buttons[1]
              ] else
                Row(children: [
                  Expanded(child: buttons[0]),
                  const SizedBox(width: 8),
                  Expanded(child: buttons[1])
                ]),
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      'Teilen mit dem Trainerteam · Familienfreigabe separat im Spieltag',
                      style: TextStyle(
                          fontSize: 11, color: context.appColors.textMuted))),
            ]);
      });

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final hinge = verticalSeparatingFeatureFor(context,
            availableWidth: constraints.maxWidth);
        final splitAtHinge = hinge != null &&
            hinge.left >= 250 &&
            constraints.maxWidth - hinge.right >= 250;
        final wide = splitAtHinge || constraints.maxWidth >= 680;
        final sideWidth = splitAtHinge
            ? constraints.maxWidth - hinge.right
            : (250 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 5)
                .clamp(250.0, 320.0);
        final pitch = LineupPitch(
            positions: positions,
            editable: editable && !saving,
            onMove: onMove,
            onMoveEnd: onMoveEnd,
            onEdit: onEdit);
        return SingleChildScrollView(
          key: const ValueKey('modern-lineup-scroll'),
          padding: const EdgeInsets.only(bottom: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!wide) ...[
              if (editable) _tools(context, false),
              Row(children: [
                Expanded(child: _summary(context)),
                IconButton(
                    tooltip: fullscreen
                        ? 'Vollbild verlassen'
                        : 'Aufstellung im Vollbild',
                    onPressed: onFullscreen,
                    icon: Icon(
                        fullscreen
                            ? Icons.close_fullscreen_rounded
                            : Icons.open_in_full_rounded,
                        size: 20))
              ]),
              pitch,
              _bank(context, false),
              _hint(context),
            ] else
              Row(
                  key: const ValueKey('modern-lineup-wide'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: pitch),
                    SizedBox(width: splitAtHinge ? hinge.width : 16),
                    SizedBox(
                        width: sideWidth,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: context.appColors.surfaceRaised,
                              borderRadius: BorderRadius.circular(16)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  const Expanded(
                                      child: Text('Aufstellung',
                                          style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700))),
                                  IconButton(
                                      tooltip: fullscreen
                                          ? 'Vollbild verlassen'
                                          : 'Aufstellung im Vollbild',
                                      onPressed: onFullscreen,
                                      icon: Icon(
                                          fullscreen
                                              ? Icons.close_fullscreen_rounded
                                              : Icons.open_in_full_rounded,
                                          size: 20))
                                ]),
                                if (editable)
                                  _tools(context, true)
                                else
                                  Text(formation),
                                _summary(context),
                                const Divider(),
                                _bank(context, true),
                                const SizedBox(height: 16),
                                const Text('C  Kapitän    ·    TW  Torwart',
                                    style: TextStyle(fontSize: 12)),
                                _hint(context),
                                if (notice != null) notice!,
                                if (editable) _actions(context),
                              ]),
                        )),
                  ]),
            if (!wide && notice != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: notice),
            if (!wide && editable) _actions(context),
          ]),
        );
      });
}

class JerseyIcon extends StatelessWidget {
  const JerseyIcon(
      {super.key,
      required this.number,
      this.goalkeeper = false,
      this.size = 44});
  final String number;
  final bool goalkeeper;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
            painter: _JerseyPainter(goalkeeper),
            child: Center(
                child: Padding(
              padding: EdgeInsets.only(top: size * .12),
              child: Text(number,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                      color: goalkeeper
                          ? const Color(0xff171d1b)
                          : const Color(0xffffe600),
                      fontWeight: FontWeight.w800,
                      fontSize: size * .43)),
            ))),
      );
}

class _JerseyPainter extends CustomPainter {
  const _JerseyPainter(this.goalkeeper);
  final bool goalkeeper;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(.32, .08)
      ..lineTo(.16, .13)
      ..lineTo(.03, .32)
      ..lineTo(.18, .46)
      ..lineTo(.27, .37)
      ..lineTo(.27, .94)
      ..lineTo(.73, .94)
      ..lineTo(.73, .37)
      ..lineTo(.82, .46)
      ..lineTo(.97, .32)
      ..lineTo(.84, .13)
      ..lineTo(.68, .08)
      ..quadraticBezierTo(.5, .27, .32, .08)
      ..close();
    canvas.save();
    canvas.scale(size.width, size.height);
    canvas.drawPath(
        path,
        Paint()
          ..color =
              goalkeeper ? const Color(0xffffe600) : const Color(0xff171d1b));
    canvas.drawPath(
        path,
        Paint()
          ..color =
              goalkeeper ? const Color(0xffe4cb18) : const Color(0xffeef4ef)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .025
          ..strokeJoin = StrokeJoin.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_JerseyPainter oldDelegate) =>
      goalkeeper != oldDelegate.goalkeeper;
}

class LineupPitch extends StatefulWidget {
  const LineupPitch(
      {super.key,
      required this.positions,
      required this.editable,
      required this.onMove,
      required this.onMoveEnd,
      required this.onEdit});
  final List<LineupPositionModel> positions;
  final bool editable;
  final void Function(int index, Offset position) onMove;
  final VoidCallback onMoveEnd;
  final ValueChanged<int> onEdit;
  @override
  State<LineupPitch> createState() => _LineupPitchState();
}

class _LineupPitchState extends State<LineupPitch> {
  final _transform = TransformationController();
  Size? _size;
  bool _dragging = false;
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  String _shortName(String fullName) =>
      fullName.trim().split(RegExp(r'\s+')).first;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context);
        final markerWidth = (constraints.maxWidth < 340 ? 66.0 : 76.0) *
            math.max(1.0, scale.scale(12) / 12);
        final nameStyle = DefaultTextStyle.of(context).style.copyWith(
            fontSize: 12,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: const Color(0xff171d1b));
        final codeStyle = nameStyle.copyWith(fontSize: 11, color: Colors.white);
        var nameHeight = scale.scale(14.0);
        var codeHeight = scale.scale(14.0);
        for (final position in widget.positions) {
          final painter = TextPainter(
              text: TextSpan(
                  text: _shortName(position.player.name), style: nameStyle),
              textDirection: Directionality.of(context),
              textScaler: scale)
            ..layout(maxWidth: markerWidth - 8);
          nameHeight = math.max(nameHeight, painter.height);
          painter.dispose();
          final codePainter = TextPainter(
              text: TextSpan(text: position.positionCode, style: codeStyle),
              textDirection: Directionality.of(context),
              textScaler: scale)
            ..layout(maxWidth: markerWidth);
          codeHeight = math.max(codeHeight, codePainter.height);
          codePainter.dispose();
        }
        final markerHeight =
            46 + nameHeight.ceilToDouble() + codeHeight.ceilToDouble() + 6;
        // Preserve saved tactical coordinates. Dense formations / large text use a
        // contained pannable field instead of shrinking labels below legibility.
        var requiredWidth = constraints.maxWidth;
        for (var i = 0; i < widget.positions.length; i++) {
          for (var j = i + 1; j < widget.positions.length; j++) {
            final a = widget.positions[i], b = widget.positions[j];
            final dx = (a.x - b.x).abs();
            if ((a.y - b.y).abs() < .08 && dx > .12) {
              requiredWidth =
                  math.max(requiredWidth, markerWidth + (markerWidth + 4) / dx);
            }
          }
        }
        var width =
            math.min(requiredWidth, math.max(constraints.maxWidth, 1000.0));
        var height = math.max(width * 1.18, markerHeight * 4.8);
        for (var i = 0; i < widget.positions.length; i++) {
          for (var j = i + 1; j < widget.positions.length; j++) {
            final a = widget.positions[i], b = widget.positions[j];
            final dy = (a.y - b.y).abs();
            if ((a.x - b.x).abs() * (width - markerWidth) < markerWidth &&
                dy > .12) {
              height = math.max(height, markerHeight + (markerHeight + 6) / dy);
            }
          }
        }
        if (_dragging && _size != null) {
          width = _size!.width;
          height = _size!.height;
        }
        final size = Size(width, height);
        if (_size != size) {
          _size = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _transform.value = Matrix4.translationValues(
                  -(width - constraints.maxWidth) / 2, 0, 0);
            }
          });
        }
        final panning = width > constraints.maxWidth + 1;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (panning)
                Row(children: [
                  const Expanded(
                      child: Text('Feld seitlich verschieben · für alle Namen',
                          style: TextStyle(fontSize: 12))),
                  IconButton(
                      tooltip: 'Feld zentrieren',
                      onPressed: () => _transform.value =
                          Matrix4.translationValues(
                              -(width - constraints.maxWidth) / 2, 0, 0),
                      icon: const Icon(Icons.center_focus_strong, size: 19))
                ]),
              SizedBox(
                  height: height,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: InteractiveViewer(
                      transformationController: _transform,
                      constrained: false,
                      panEnabled: panning,
                      scaleEnabled: false,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                          width: width,
                          height: height,
                          child: Stack(
                              key: const ValueKey('modern-lineup-pitch'),
                              children: [
                                const Positioned.fill(
                                    child: CustomPaint(
                                        painter: LineupFieldPainter())),
                                for (var i = 0;
                                    i < widget.positions.length;
                                    i++)
                                  Positioned(
                                    left: widget.positions[i].x.clamp(0, 1) *
                                        (width - markerWidth),
                                    top: widget.positions[i].y.clamp(0, 1) *
                                        (height - markerHeight),
                                    width: markerWidth,
                                    height: markerHeight,
                                    child: Semantics(
                                      button: true,
                                      label:
                                          '${widget.positions[i].player.name}, ${widget.positions[i].positionCode}${widget.positions[i].isCaptain ? ', Kapitän' : ''}',
                                      child: Tooltip(
                                        message:
                                            widget.positions[i].player.name,
                                        child: GestureDetector(
                                          key: ValueKey(
                                              'lineup-player-${widget.positions[i].player.id}'),
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            if (widget.editable) {
                                              widget.onEdit(i);
                                            } else {
                                              showDialog<void>(
                                                  context: context,
                                                  builder: (c) => AlertDialog(
                                                          title: Text(widget
                                                              .positions[i]
                                                              .player
                                                              .name),
                                                          content: Text(
                                                              '${widget.positions[i].positionCode}${widget.positions[i].isCaptain ? ' · Kapitän' : ''}'),
                                                          actions: [
                                                            TextButton(
                                                                onPressed: () =>
                                                                    Navigator
                                                                        .pop(c),
                                                                child: const Text(
                                                                    'Schließen'))
                                                          ]));
                                            }
                                          },
                                          onPanStart: widget.editable
                                              ? (_) => _dragging = true
                                              : null,
                                          onPanUpdate: widget.editable
                                              ? (event) {
                                                  final p = widget.positions[i];
                                                  widget.onMove(
                                                      i,
                                                      Offset(
                                                          (p.x +
                                                                  event.delta
                                                                          .dx /
                                                                      (width -
                                                                          markerWidth))
                                                              .clamp(0, 1),
                                                          (p.y +
                                                                  event.delta
                                                                          .dy /
                                                                      (height -
                                                                          markerHeight))
                                                              .clamp(0, 1)));
                                                }
                                              : null,
                                          onPanEnd: widget.editable
                                              ? (_) {
                                                  setState(
                                                      () => _dragging = false);
                                                  widget.onMoveEnd();
                                                }
                                              : null,
                                          onPanCancel: widget.editable
                                              ? () {
                                                  setState(
                                                      () => _dragging = false);
                                                  widget.onMoveEnd();
                                                }
                                              : null,
                                          child: Column(children: [
                                            SizedBox(
                                                height: 46,
                                                child: Stack(
                                                    clipBehavior: Clip.none,
                                                    children: [
                                                      JerseyIcon(
                                                          number: widget
                                                                  .positions[i]
                                                                  .player
                                                                  .shirtNumber
                                                                  ?.toString() ??
                                                              '–',
                                                          goalkeeper: widget
                                                              .positions[i]
                                                              .isGoalkeeper),
                                                      if (widget.positions[i]
                                                          .isCaptain)
                                                        Positioned(
                                                            top: 0,
                                                            right: -7,
                                                            child: Container(
                                                                width: 19,
                                                                height: 19,
                                                                alignment:
                                                                    Alignment
                                                                        .center,
                                                                decoration: BoxDecoration(
                                                                    color: AppColors
                                                                        .yellow,
                                                                    shape: BoxShape
                                                                        .circle,
                                                                    border: Border.all(
                                                                        color: const Color(
                                                                            0xff171d1b))),
                                                                child: const Text(
                                                                    'C',
                                                                    textScaler:
                                                                        TextScaler
                                                                            .noScaling,
                                                                    style: TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        color:
                                                                            Color(0xff171d1b),
                                                                        fontWeight: FontWeight.w800)))),
                                                    ])),
                                            Container(
                                                width: markerWidth - 4,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 2,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xfff8fbf8),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            5)),
                                                child: Text(
                                                    _shortName(widget
                                                        .positions[i]
                                                        .player
                                                        .name),
                                                    textAlign: TextAlign.center,
                                                    style: nameStyle)),
                                            Text(
                                                widget
                                                    .positions[i].positionCode,
                                                style: codeStyle),
                                          ]),
                                        ),
                                      ),
                                    ),
                                  ),
                              ])),
                    ),
                  )),
            ]);
      });
}

class LineupFieldPainter extends CustomPainter {
  const LineupFieldPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xff17644d));
    for (var i = 0; i < 10; i += 2) {
      canvas.drawRect(
          Rect.fromLTWH(0, size.height * i / 10, size.width, size.height / 10),
          Paint()..color = const Color(0xff1b6d54));
    }
    final paint = Paint()
      ..color = const Color(0x80d7eee1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rect = Rect.fromLTWH(14, 12, size.width - 28, size.height - 24);
    canvas.drawRect(rect, paint);
    canvas.drawLine(Offset(rect.left, rect.center.dy),
        Offset(rect.right, rect.center.dy), paint);
    canvas.drawCircle(rect.center, rect.width * .14, paint);
    canvas.drawCircle(rect.center, 2, Paint()..color = paint.color);
    for (final bottom in [false, true]) {
      for (final box in [(0.6, 0.16), (0.3, 0.065)]) {
        final w = rect.width * box.$1, h = rect.height * box.$2;
        canvas.drawRect(
            Rect.fromLTWH(rect.center.dx - w / 2,
                bottom ? rect.bottom - h : rect.top, w, h),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(LineupFieldPainter oldDelegate) => false;
}
