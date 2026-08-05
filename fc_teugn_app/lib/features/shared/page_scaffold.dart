import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
    this.denseMobileHeader = false,
    this.hideMobileHeader = false,
    this.fillRemaining = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;
  final bool denseMobileHeader;
  final bool hideMobileHeader;
  final bool fillRemaining;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;
        final horizontal = constraints.maxWidth >= 700 ? 32.0 : 14.0;
        final compactHeader = constraints.maxWidth < 640;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: denseMobileHeader && mobile ? 1 : null,
              overflow:
                  denseMobileHeader && mobile ? TextOverflow.ellipsis : null,
              style: mobile
                  ? denseMobileHeader
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.headlineSmall
                  : Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: mobile ? (denseMobileHeader ? 2 : 4) : 6),
            Text(
              subtitle,
              maxLines: denseMobileHeader && mobile ? 1 : null,
              overflow:
                  denseMobileHeader && mobile ? TextOverflow.ellipsis : null,
              style: (mobile
                      ? denseMobileHeader
                          ? Theme.of(context).textTheme.bodySmall
                          : Theme.of(context).textTheme.bodyMedium
                      : Theme.of(context).textTheme.bodyLarge)
                  ?.copyWith(
                color: AppColors.muted,
              ),
            ),
          ],
        );
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
            if (!(mobile && hideMobileHeader))
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  mobile ? (denseMobileHeader ? 10 : 18) : 28,
                  horizontal,
                  mobile ? (denseMobileHeader ? 10 : 14) : 18,
                ),
                sliver: SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: compactHeader
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              titleBlock,
                              if (action != null) ...[
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: action!,
                                ),
                              ],
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: titleBlock),
                              if (action != null) ...[
                                const SizedBox(width: 16),
                                action!,
                              ],
                            ],
                          ),
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontal,
                mobile && hideMobileHeader ? 6 : 0,
                horizontal,
                mobile ? 20 : 32,
              ),
              sliver: fillRemaining
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: child,
                      ),
                    )
                  : SliverToBoxAdapter(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: child,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.line),
    );
    return Material(
      color: Colors.white,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 18),
          child: Row(
            children: [
              Container(
                width: compact ? 40 : 46,
                height: compact ? 40 : 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: compact ? 21 : 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                    ),
                    if (caption != null)
                      Text(
                        caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.muted,
                            ),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 54),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: AppColors.blue, size: 28),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}
