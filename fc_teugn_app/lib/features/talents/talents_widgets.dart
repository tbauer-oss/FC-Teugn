import 'package:flutter/material.dart';
import 'talents_repository.dart';

class TalentsAsync extends StatelessWidget {
  const TalentsAsync(
      {super.key,
      required this.future,
      required this.onRetry,
      required this.builder});
  final Future<dynamic> future;
  final VoidCallback onRetry;
  final Widget Function(dynamic data) builder;
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return TalentsEmpty(
              icon: Icons.cloud_off,
              text: talentsError(snapshot.error!),
              action: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Erneut laden')));
        }
        return builder(snapshot.data);
      });
}

class TalentsEmpty extends StatelessWidget {
  const TalentsEmpty(
      {super.key,
      required this.text,
      this.icon = Icons.check_circle_outline,
      this.action});
  final String text;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 28),
      child: Column(children: [
        Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ]));
}

class TalentsCard extends StatelessWidget {
  const TalentsCard(
      {super.key, required this.title, this.subtitle, required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
          padding:
              EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 12 : 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall)
            ],
            const SizedBox(height: 12),
            ...children,
          ])));
}

Future<bool> talentsForm(BuildContext context,
    {required String title,
    required Json initial,
    required List<Widget> Function(
            Json values, void Function(String, dynamic) set)
        fields,
    required Future<void> Function(Json values) save,
    String saveLabel = 'Speichern'}) async {
  final values = Map<String, dynamic>.from(initial);
  final key = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => StatefulBuilder(
                builder: (context, update) => PopScope(
                    canPop: !busy,
                    child: AlertDialog(
                      title: Text(title),
                      scrollable: true,
                      content: SizedBox(
                          width: 560,
                          child: Form(
                              key: key,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ...fields(
                                        values,
                                        (key, value) => update(
                                            () => values[key] = value)).expand(
                                        (field) => [
                                              field,
                                              const SizedBox(height: 14)
                                            ]),
                                    const Text(
                                        'Zum Speichern ist eine Internetverbindung erforderlich.',
                                        style: TextStyle(fontSize: 12)),
                                    if (error != null)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 12),
                                          child: Semantics(
                                              liveRegion: true,
                                              child: Text(error!,
                                                  style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .error)))),
                                  ]))),
                      actions: [
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => Navigator.pop(context, false),
                            child: const Text('Abbrechen')),
                        FilledButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    if (!key.currentState!.validate()) return;
                                    update(() {
                                      busy = true;
                                      error = null;
                                    });
                                    try {
                                      await save(values);
                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext, true);
                                      }
                                    } catch (e) {
                                      if (dialogContext.mounted) {
                                        update(() {
                                          busy = false;
                                          error = talentsError(e);
                                        });
                                      }
                                    }
                                  },
                            child: busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Text(saveLabel)),
                      ],
                    )),
              )) ??
      false;
}

Widget textInput(Json values, void Function(String, dynamic) set, String key,
        String label,
        {bool required = true, int lines = 1, TextInputType? keyboard}) =>
    TextFormField(
      initialValue: values[key]?.toString() ?? '',
      maxLines: lines,
      keyboardType: keyboard,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
      onChanged: (value) => set(key, value),
      validator: (value) => required && (value == null || value.trim().isEmpty)
          ? 'Bitte ausfüllen.'
          : null,
    );
Widget choiceInput(Json values, void Function(String, dynamic) set, String key,
        String label, Map<String, String> choices) =>
    DropdownButtonFormField<String>(
      itemHeight: null,
      key: ValueKey('$key-${values[key]}-${choices.keys.join()}'),
      isExpanded: true,
      initialValue:
          choices.containsKey(values[key]) ? values[key] as String : null,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: choices.entries
          .map((e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (value) => set(key, value),
      validator: (value) => value == null ? 'Bitte auswählen.' : null,
    );
Widget multipleInput(Json values, void Function(String, dynamic) set,
    String key, String label, Map<String, String> choices) {
  final selected = Set<String>.from(values[key] as List? ?? const []);
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label),
    const SizedBox(height: 6),
    Wrap(
        spacing: 8,
        runSpacing: 4,
        children: choices.entries
            .map((e) => FilterChip(
                label: Text(e.value),
                selected: selected.contains(e.key),
                onSelected: (yes) {
                  yes ? selected.add(e.key) : selected.remove(e.key);
                  set(key, selected.toList());
                }))
            .toList()),
  ]);
}

Widget dayInput(BuildContext context, Json values,
        void Function(String, dynamic) set, String key, String label) =>
    OutlinedButton.icon(
        icon: const Icon(Icons.calendar_month),
        label: Text('$label: ${showDate(values[key])}'),
        onPressed: () async {
          final date = DateTime.tryParse(values[key]?.toString() ?? '') ??
              DateTime.now();
          final chosen = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2020),
              lastDate: DateTime(DateTime.now().year + 5));
          if (chosen != null) set(key, dateString(chosen));
        });
