import 'package:flutter/material.dart';
import '../loading/loading_widgets.dart';
import 'adaptive_layout.dart';

/// Einheitlicher, tastaturfester Bearbeitungsdialog für App und Web.
///
/// Auf kleinen Displays nutzt er die gesamte verfügbare Fläche mit einer
/// festen Kopf- und Aktionsleiste. Auf Desktop bleibt er ein zentrierter
/// Dialog. Dadurch bleiben Überschriften, Eingabefelder und Speichern immer
/// erreichbar, auch bei großer Systemschrift.
class ResponsiveFormDialog extends StatelessWidget {
  const ResponsiveFormDialog({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.subtitle,
    this.saveLabel = 'Speichern',
    this.saveIcon = Icons.save_outlined,
    this.maxWidth = 720,
    this.saving = false,
    this.preferInlineActions = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback? onSave;
  final String saveLabel;
  final IconData saveIcon;
  final double maxWidth;
  final bool saving;
  final bool preferInlineActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdaptiveDialogScaffold(
      title: title,
      subtitle: subtitle,
      maxWidth: maxWidth,
      preferInlineActions: preferInlineActions,
      content: Theme(
        data: theme.copyWith(
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            isDense: true,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            contentPadding: const EdgeInsets.fromLTRB(16, 17, 16, 15),
            helperMaxLines: 2,
            errorMaxLines: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: saving ? null : onSave,
          icon: saving
              ? const LogoLoadingIndicator(
                  size: 22,
                  semanticsLabel: 'Änderungen werden gespeichert',
                )
              : Icon(saveIcon),
          label: Text(saveLabel),
        ),
      ],
    );
  }
}

class ResponsiveFormSection extends StatelessWidget {
  const ResponsiveFormSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class ResponsiveFormRow extends StatelessWidget {
  const ResponsiveFormRow({
    super.key,
    required this.children,
    this.breakpoint = 560,
    this.spacing = 12,
  });

  final List<Widget> children;
  final double breakpoint;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final effectiveBreakpoint = breakpoint * textScale.clamp(1, 1.45);
          if (constraints.maxWidth < effectiveBreakpoint) {
            return Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index != children.length - 1) SizedBox(height: spacing),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                Expanded(child: children[index]),
                if (index != children.length - 1) SizedBox(width: spacing),
              ],
            ],
          );
        },
      );
}
