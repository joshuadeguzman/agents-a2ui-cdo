import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../theme/app_theme.dart';
import 'binding.dart';
import 'catalog_schemas.g.dart';
import 'children.dart';

/// Vertical spacing for a Stack `gap` value.
double stackGap(Object? gap) => switch (gap) {
  'small' => Gaps.md,
  'large' => Gaps.xxl,
  _ => Gaps.xl,
};

/// `Stack`: vertical layout, always the surface root.
final CatalogItem stackItem = CatalogItem(
  name: 'Stack',
  dataSchema: Schema.fromMap(stackSchema),
  widgetBuilder: (itemContext) {
    final Map<String, Object?> props = propsOf(itemContext);
    return SurfaceChildren(
      itemContext: itemContext,
      children: props['children'],
      builder: (context, children) =>
          SiargaoStack(gap: stackGap(props['gap']), children: children),
    );
  },
);

/// The Flutter widget behind `Stack`.
class SiargaoStack extends StatelessWidget {
  /// Creates a [SiargaoStack].
  const SiargaoStack({super.key, required this.children, this.gap = Gaps.xl});

  /// Children, top to bottom.
  final List<Widget> children;

  /// Space between children.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gap,
      children: children,
    );
  }
}
