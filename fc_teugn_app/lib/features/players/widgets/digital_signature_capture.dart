import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';

class DigitalSignatureCapture extends StatelessWidget {
  const DigitalSignatureCapture({
    super.key,
    required this.signatureData,
    required this.onChanged,
  });

  final Map<String, dynamic>? signatureData;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasSignature = signatureData != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Unterschrift',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('open-signature-dialog'),
          onPressed: () => _openDialog(context),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size.fromHeight(58),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          icon: Icon(
            hasSignature ? Icons.edit_outlined : Icons.draw_outlined,
          ),
          label: Text(
            hasSignature
                ? 'Unterschrift ansehen oder ändern'
                : 'Unterschrift hinzufügen',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              hasSignature
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              size: 18,
              color: hasSignature ? AppColors.success : AppColors.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasSignature
                    ? 'Unterschrift wurde übernommen.'
                    : 'Öffnet ein großes Feld für Finger, Eingabestift oder Maus.',
                style: TextStyle(
                  color: hasSignature ? AppColors.success : AppColors.muted,
                  fontSize: 12,
                  fontWeight:
                      hasSignature ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openDialog(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DigitalSignatureDialog(
        replacingExistingSignature: signatureData != null,
      ),
    );
    if (result != null) onChanged(result);
  }
}

class _DigitalSignatureDialog extends StatefulWidget {
  const _DigitalSignatureDialog({
    required this.replacingExistingSignature,
  });

  final bool replacingExistingSignature;

  @override
  State<_DigitalSignatureDialog> createState() =>
      _DigitalSignatureDialogState();
}

class _DigitalSignatureDialogState extends State<_DigitalSignatureDialog> {
  final signatureKey = GlobalKey<_SignaturePadState>();
  String? error;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    final stackActions = size.width < 900;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 32,
        vertical: compact ? 8 : 24,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
        child: SizedBox(
          width: double.maxFinite,
          height: compact ? size.height - 16 : 680,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 24,
                  14,
                  8,
                  12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.yellow.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.draw_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Digital unterschreiben',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Text(
                            'Mit Finger, Eingabestift oder Maus unterschreiben.',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
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
              if (widget.replacingExistingSignature)
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.fromLTRB(
                    compact ? 12 : 24,
                    12,
                    compact ? 12 : 24,
                    0,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F1E5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Die bisherige Unterschrift bleibt gespeichert, bis du eine neue Unterschrift übernimmst.',
                    style: TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(compact ? 12 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _SignaturePad(key: signatureKey),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.all(compact ? 12 : 16),
                child: stackActions
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('accept-signature'),
                            onPressed: _accept,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Unterschrift übernehmen'),
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: _clear,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Neu beginnen'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Abbrechen'),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _clear,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Neu beginnen'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Abbrechen'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            key: const ValueKey('accept-signature'),
                            onPressed: _accept,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Unterschrift übernehmen'),
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

  void _clear() {
    signatureKey.currentState?.clear();
    setState(() => error = null);
  }

  void _accept() {
    final signature = signatureKey.currentState?.data;
    if (signature == null) {
      setState(
        () => error =
            'Bitte zuerst im großen Unterschriftsfeld unterschreiben.',
      );
      return;
    }
    Navigator.pop(context, signature);
  }
}

class _SignaturePad extends StatefulWidget {
  const _SignaturePad({super.key});

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final strokes = <List<Offset>>[];
  Size size = Size.zero;

  Map<String, dynamic>? get data {
    final points = strokes.expand((stroke) => stroke).length;
    if (points < 8 || size.isEmpty) return null;
    return {
      'width': size.width,
      'height': size.height,
      'strokes': [
        for (final stroke in strokes)
          [
            for (final point in stroke) {'x': point.dx, 'y': point.dy},
          ],
      ],
    };
  }

  void clear() => setState(strokes.clear);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          key: const ValueKey('digital-signature-pad'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => setState(() {
            strokes.add([_inside(details.localPosition)]);
          }),
          onPanUpdate: (details) => setState(() {
            if (strokes.isEmpty) strokes.add([]);
            strokes.last.add(_inside(details.localPosition));
          }),
          child: CustomPaint(
            painter: _SignaturePainter(strokes),
            size: size,
            child: strokes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.gesture_rounded,
                            size: 42,
                            color: AppColors.muted,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Hier unterschreiben',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  Offset _inside(Offset point) => Offset(
        point.dx.clamp(0, size.width),
        point.dy.clamp(0, size.height),
      );
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFFFFEF8);
    final border = Paint()
      ..color = const Color(0xFFC8C3B2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    canvas.drawRRect(rect, background);
    canvas.drawRRect(rect, border);

    final guide = Paint()
      ..color = const Color(0xFFD8D5C8)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(24, size.height * 0.72),
      Offset(size.width - 24, size.height * 0.72),
      guide,
    );

    final ink = Paint()
      ..color = AppColors.black
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.clipRRect(rect);
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
