import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Title row at the top of each screen with labels on the right.
class ScreenHeader extends StatelessWidget {
  /// Creates a [ScreenHeader].
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.badges = const [],
    this.trailing,
  });

  /// Screen title.
  final String title;

  /// One line under the title.
  final String? subtitle;

  /// Small labels such as the delivery path.
  final List<Widget> badges;

  /// Extra control on the right, such as a toggle.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool narrow = constraints.maxWidth < 640;
        final Widget titles = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: narrow ? t.headlineSmall : t.headlineMedium),
            if (subtitle != null && !narrow) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: t.bodyMedium?.copyWith(color: AppColors.inkMuted),
              ),
            ],
          ],
        );
        final Widget badgeWrap = Wrap(
          spacing: Gaps.sm,
          runSpacing: Gaps.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: badges,
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: titles),
                  ?trailing,
                ],
              ),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: Gaps.sm),
                badgeWrap,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titles),
            const SizedBox(width: Gaps.lg),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Gaps.sm,
              children: badges,
            ),
            if (trailing != null) ...[
              const SizedBox(width: Gaps.lg),
              trailing!,
            ],
          ],
        );
      },
    );
  }
}

/// Centers content and limits its width.
class ContentWidth extends StatelessWidget {
  /// Creates a [ContentWidth].
  const ContentWidth({super.key, required this.child, this.maxWidth = 1180});

  /// Content.
  final Widget child;

  /// Maximum width.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Horizontal page padding for a given width.
EdgeInsets pagePadding(double width) =>
    EdgeInsets.symmetric(horizontal: width < 640 ? Gaps.lg : Gaps.xxl);
