import 'package:flutter/material.dart';
import '../loading/loading_widgets.dart';

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
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback? onSave;
  final String saveLabel;
  final IconData saveIcon;
  final double maxWidth;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final mobile = media.size.width < 600;
    final theme = Theme.of(context);
    final body = Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          isDense: true,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          contentPadding: const EdgeInsets.fromLTRB(16, 17, 16, 15),
          helperMaxLines: 2,
          errorMaxLines: 2,
        ),
      ),
      child: Material(
        color: theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface,
        borderRadius: mobile ? BorderRadius.zero : BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: mobile ? media.size.width : maxWidth,
          height: mobile ? media.size.height : media.size.height * .88,
          child: SafeArea(
            child: Column(
              children: [
                _DialogHeader(title: title, subtitle: subtitle),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 16 : 24,
                      18,
                      mobile ? 16 : 24,
                      24 + media.viewInsets.bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
                const Divider(height: 1),
                _DialogActions(
                  saveLabel: saveLabel,
                  saveIcon: saveIcon,
                  saving: saving,
                  onSave: onSave,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Dialog(
      insetPadding: mobile ? EdgeInsets.zero : const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.none,
      child: body,
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
          if (constraints.maxWidth < breakpoint) {
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

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Schließen',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      );
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.saveLabel,
    required this.saveIcon,
    required this.saving,
    required this.onSave,
  });

  final String saveLabel;
  final IconData saveIcon;
  final bool saving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, mobile ? 12 : 14),
      child: Row(
        children: [
          if (!mobile)
            TextButton(
              onPressed: saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
          if (!mobile) const Spacer(),
          if (mobile)
            Expanded(
              child: OutlinedButton(
                onPressed: saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Abbrechen'),
              ),
            ),
          if (mobile) const SizedBox(width: 10),
          if (mobile)
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const LogoLoadingIndicator(
                        size: 22,
                        semanticsLabel: 'Änderungen werden gespeichert',
                      )
                    : Icon(saveIcon),
                label: Text(saveLabel),
              ),
            )
          else
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
      ),
    );
  }
}
