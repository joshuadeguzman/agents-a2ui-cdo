import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../theme/app_theme.dart';
import 'binding.dart';
import 'catalog_schemas.g.dart';
import 'flex_grid.dart';
import 'image_asset.dart';

/// `Heading`: page or section header with optional eyebrow, subtitle and a
/// 16:9 hero image. Inside a `FlexGrid` it renders as a tile card.
final CatalogItem headingItem = CatalogItem(
  name: 'Heading',
  dataSchema: Schema.fromMap(headingSchema),
  widgetBuilder: (itemContext) {
    final Map<String, Object?> props = propsOf(itemContext);
    return BoundProps(
      dataContext: itemContext.dataContext,
      props: {
        'title': props['title'],
        'subtitle': props['subtitle'],
        'eyebrow': props['eyebrow'],
        'image': props['image'],
      },
      builder: (context, v) => SiargaoHeading(
        title: v.string('title') ?? '',
        subtitle: v.string('subtitle'),
        eyebrow: v.string('eyebrow'),
        imageKey: v.string('image'),
      ),
    );
  },
);

/// The Flutter widget behind `Heading`.
class SiargaoHeading extends StatelessWidget {
  /// Creates a [SiargaoHeading].
  const SiargaoHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.imageKey,
  });

  /// Title text.
  final String title;

  /// Optional supporting sentence.
  final String? subtitle;

  /// Optional small uppercase label.
  final String? eyebrow;

  /// Optional image key.
  final String? imageKey;

  bool get _isSection =>
      imageKey == null && subtitle == null && eyebrow == null;

  @override
  Widget build(BuildContext context) {
    if (GridItemScope.isInGrid(context)) return _tile(context);
    if (_isSection) return _section(context);
    return _hero(context);
  }

  Widget _eyebrow(BuildContext context) => Text(
    eyebrow!.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AppColors.teal, letterSpacing: 1.1),
  );

  Widget _section(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Gaps.sm),
      child: Text(
        noWidow(title),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }

  Widget _texts(BuildContext context, {required bool large}) {
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[_eyebrow(context), const SizedBox(height: 10)],
        Text(noWidow(title), style: large ? t.headlineLarge : t.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: Gaps.md),
          Text(
            noWidow(subtitle!),
            style: t.bodyLarge?.copyWith(color: AppColors.inkMuted),
          ),
        ],
      ],
    );
  }

  Widget _hero(BuildContext context) {
    if (imageKey == null) return _texts(context, large: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= 760;
        final Widget image = SiargaoImage(
          imageKey: imageKey,
          aspectRatio: 16 / 9,
        );
        if (!wide) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              image,
              const SizedBox(height: Gaps.xl),
              _texts(context, large: false),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: image),
            const SizedBox(width: Gaps.xxl),
            Expanded(child: _texts(context, large: true)),
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageKey != null)
            SiargaoImage(
              imageKey: imageKey,
              aspectRatio: 3 / 2,
              borderRadius: BorderRadius.zero,
            ),
          Padding(
            padding: const EdgeInsets.all(Gaps.xl - 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  _eyebrow(context),
                  const SizedBox(height: Gaps.sm),
                ],
                Text(noWidow(title), style: t.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: Gaps.sm),
                  Text(
                    subtitle!,
                    style: t.bodyMedium?.copyWith(color: AppColors.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
