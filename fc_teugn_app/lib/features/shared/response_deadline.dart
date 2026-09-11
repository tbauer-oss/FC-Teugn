import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

String responseDeadlineDate(DateTime value) {
  final date = value.toLocal();
  return '${date.day}.${date.month}.${date.year} · '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} Uhr';
}

class ResponseDeadlineField extends StatelessWidget {
  const ResponseDeadlineField(
      {super.key,
      required this.startAt,
      required this.value,
      required this.onChanged});
  final DateTime startAt;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final initial =
        (value ?? startAt.subtract(const Duration(days: 1))).toLocal();
    final date = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(initial.year - 1),
        lastDate: DateTime(startAt.year + 1, 12, 31));
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return;
    onChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) => FormField<DateTime>(
        validator: (_) => value != null && !value!.isBefore(startAt)
            ? 'Die Rückmeldefrist muss vor dem Spielbeginn liegen.'
            : null,
        builder: (field) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: context.appInfo.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: context.appInfo.withValues(alpha: .22))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.lock_clock_outlined, size: 20),
              SizedBox(width: 8),
              Expanded(
                  child: Text('Kader schließen',
                      style: TextStyle(fontWeight: FontWeight.w800)))
            ]),
            const SizedBox(height: 6),
            const Text(
                'Bis wann dürfen Eltern zu- oder absagen? Danach kann nur noch das Trainerteam Rückmeldungen ändern.'),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              ChoiceChip(
                  label: const Text('Ohne Frist'),
                  selected: value == null,
                  onSelected: (_) => onChanged(null)),
              for (final hours in const [24, 48, 72, 168, 336])
                ChoiceChip(
                    label: Text(hours < 168
                        ? '$hours h vorher'
                        : '${hours ~/ 24} Tage vorher'),
                    selected: value != null &&
                        startAt.difference(value!) == Duration(hours: hours),
                    onSelected: (_) =>
                        onChanged(startAt.subtract(Duration(hours: hours)))),
              ActionChip(
                  avatar: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: const Text('Zeitpunkt wählen'),
                  onPressed: () => _pick(context)),
            ]),
            if (value != null) ...[
              const SizedBox(height: 8),
              Text('Frist: ${responseDeadlineDate(value!)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (!value!.isAfter(DateTime.now()))
                const Text(
                    'Dieser Zeitpunkt ist bereits erreicht. Nach dem Speichern können nur Trainer Änderungen vornehmen.'),
              const SizedBox(height: 4),
              const Text(
                  'Die Frist wird mit der Familienfreigabe und Spielinfo kommuniziert. Beim Verschieben des Beginns bleibt der zeitliche Abstand erhalten.'),
            ],
            if (field.hasError)
              Text(field.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
      );
}

/// Rebuilds exactly at cutoff, including screens that remain open.
class ResponseDeadlineGate extends StatefulWidget {
  const ResponseDeadlineGate(
      {super.key, required this.deadline, required this.builder});
  final DateTime? deadline;
  final Widget Function(BuildContext, bool closed) builder;
  @override
  State<ResponseDeadlineGate> createState() => _ResponseDeadlineGateState();
}

class _ResponseDeadlineGateState extends State<ResponseDeadlineGate> {
  Timer? _timer;
  bool _expired = false;
  void _schedule() {
    _timer?.cancel();
    final delay = widget.deadline?.difference(DateTime.now());
    _expired = delay != null && delay <= Duration.zero;
    if (delay != null && delay > Duration.zero) {
      _timer = Timer(delay, () {
        if (mounted) {
          setState(() {
            _expired = true;
          });
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ResponseDeadlineGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
      context,
      _expired ||
          (widget.deadline != null &&
              !widget.deadline!.isAfter(DateTime.now())));
}

class ResponseDeadlineNotice extends StatelessWidget {
  const ResponseDeadlineNotice(
      {super.key, required this.deadline, this.staffView = false});
  final DateTime? deadline;
  final bool staffView;
  @override
  Widget build(BuildContext context) {
    if (deadline == null) return const SizedBox.shrink();
    return ResponseDeadlineGate(
        deadline: deadline,
        builder: (context, closed) => Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: (closed ? context.appWarning : context.appInfo)
                      .withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12)),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                    closed
                        ? Icons.lock_outline_rounded
                        : Icons.lock_clock_outlined,
                    size: 20,
                    color: closed ? context.appWarning : context.appInfo),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          '${closed ? 'Kader geschlossen seit' : 'Kader schließt am'} ${responseDeadlineDate(deadline!)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(closed
                          ? staffView
                              ? 'Eltern können nicht mehr antworten. Du kannst als Trainer weiterhin Zu- und Absagen ändern.'
                              : 'Zu- und Absagen sind nur noch durch das Trainerteam möglich. Bitte bei Änderungen direkt Kontakt aufnehmen.'
                          : 'Danach sind Zu- und Absagen nur noch durch das Trainerteam möglich.'),
                    ])),
              ]),
            ));
  }
}
