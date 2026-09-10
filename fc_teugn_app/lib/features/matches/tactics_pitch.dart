import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/tactics_board.dart';

const tacticsYellow = Color(0xFFFFE600);
const tacticsInk = Color(0xFF101C20);
const tacticsColors = <String, Color>{
  'yellow': tacticsYellow,
  'cyan': Color(0xFF65D9ED),
  'white': Colors.white,
  'red': Color(0xFFFF8F8F),
};

/// Logical coordinates always describe the upright pitch, regardless of rotation.
Offset tacticsToScreen(Offset point, Size size, bool landscape) {
  final p = landscape ? Offset(1 - point.dy, point.dx) : point;
  return Offset(28 + p.dx * math.max(1, size.width - 56),
      28 + p.dy * math.max(1, size.height - 56));
}

Offset tacticsFromScreen(Offset point, Size size, bool landscape) {
  final p = Offset(((point.dx - 28) / math.max(1, size.width - 56)).clamp(0, 1),
      ((point.dy - 28) / math.max(1, size.height - 56)).clamp(0, 1));
  return landscape ? Offset(p.dy, 1 - p.dx) : p;
}

double tacticsSegmentDistance(Offset p, Offset a, Offset b) {
  final d = b - a;
  if (d.distanceSquared == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / d.distanceSquared)
      .clamp(0.0, 1.0);
  return (p - (a + d * t)).distance;
}

class TacticsPitchPainter extends CustomPainter {
  TacticsPitchPainter({required this.strokes, required this.landscape});
  final List<TacticsStroke> strokes;
  final bool landscape;

  @override
  void paint(Canvas canvas, Size size) {
    final round =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    canvas.save();
    canvas.clipRRect(round);
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF176A50));
    for (var i = 0; i < 10; i += 2) {
      canvas.drawRect(
          landscape
              ? Rect.fromLTWH(
                  size.width * i / 10, 0, size.width / 10, size.height)
              : Rect.fromLTWH(
                  0, size.height * i / 10, size.width, size.height / 10),
          Paint()..color = const Color(0xFF1B7356));
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    Offset at(double x, double y) =>
        tacticsToScreen(Offset(x, y), size, landscape);
    void rect(double l, double t, double r, double b) =>
        canvas.drawRect(Rect.fromPoints(at(l, t), at(r, b)), line);
    rect(0, 0, 1, 1);
    canvas.drawLine(at(0, .5), at(1, .5), line);
    final unit = math.min(size.width - 56, size.height - 56);
    canvas.drawCircle(at(.5, .5), math.max(1, unit * .145), line);
    canvas.drawCircle(at(.5, .5), 2.5, Paint()..color = line.color);
    for (final top in [true, false]) {
      rect(.21, top ? 0 : .82, .79, top ? .18 : 1);
      rect(.36, top ? 0 : .935, .64, top ? .065 : 1);
      canvas.drawCircle(
          at(.5, top ? .12 : .88), 2, Paint()..color = line.color);
      rect(.43, top ? -.018 : 1, .57, top ? 0 : 1.018);
    }
    for (final stroke in strokes) {
      final pts = stroke.points
          .map((p) => tacticsToScreen(p, size, landscape))
          .toList();
      if (pts.length < 2) continue;
      final color = tacticsColors[stroke.color] ?? tacticsYellow;
      final pen = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (stroke.kind == 'zone') {
        final region = RRect.fromRectAndRadius(
            Rect.fromPoints(pts.first, pts.last), const Radius.circular(6));
        canvas.drawRRect(region, Paint()..color = color.withValues(alpha: .18));
        canvas.drawRRect(region, pen..strokeWidth = 2);
      } else if (stroke.kind == 'pen') {
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (final p in pts.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, pen);
      } else {
        final a = pts.first, b = pts.last, length = (b - a).distance;
        if (length < 1) continue;
        final direction = (b - a) / length;
        if (stroke.kind == 'run') {
          for (double d = 0; d < length; d += 14) {
            canvas.drawLine(a + direction * d,
                a + direction * math.min(d + 7, length), pen);
          }
        } else {
          canvas.drawLine(a, b, pen);
        }
        final normal = Offset(-direction.dy, direction.dx);
        final head = math.min(12.0, length * .35);
        canvas.drawPath(
            Path()
              ..moveTo((b - direction * head + normal * head * .55).dx,
                  (b - direction * head + normal * head * .55).dy)
              ..lineTo(b.dx, b.dy)
              ..lineTo((b - direction * head - normal * head * .55).dx,
                  (b - direction * head - normal * head * .55).dy),
            pen);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TacticsPitchPainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.landscape != landscape;
}

class TacticsMarker extends StatelessWidget {
  const TacticsMarker({super.key, required this.token, required this.onTap});
  final TacticsToken token;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final own = token.kind == 'own';
    final ball = token.kind == 'ball';
    final text = token.kind == 'text';
    final initials = token.label
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s.characters.first)
        .join();
    return Semantics(
      label:
          '${own ? 'Eigener Spieler' : ball ? 'Ball' : text ? 'Beschriftung' : 'Gegner'}: ${token.label}',
      button: onTap != null,
      onTap: onTap,
      child: Tooltip(
          message: token.label,
          child: ExcludeSemantics(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!text)
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ball
                          ? Colors.white
                          : own
                              ? tacticsYellow
                              : const Color(0xFF65D9ED),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .85), width: 2),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x50000000),
                            blurRadius: 5,
                            offset: Offset(0, 2))
                      ]),
                  child: Center(
                      child: ball
                          ? const Icon(Icons.sports_soccer,
                              size: 24, color: tacticsInk)
                          : Text(initials,
                              textScaler: TextScaler.noScaling,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: tacticsInk))),
                ),
              if (!ball)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                      color: tacticsInk.withValues(alpha: .88),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(token.label,
                      maxLines: text ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                          fontSize: text ? 12 : 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
            ],
          ))),
    );
  }
}
