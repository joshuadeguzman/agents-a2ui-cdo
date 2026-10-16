import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../theme/app_theme.dart';
import 'binding.dart';
import 'catalog_schemas.g.dart';
import 'children.dart';

/// `FlexGrid`: responsive grid; columns stay at least `minItemWidth` wide.
final CatalogItem flexGridItem = CatalogItem(
  name: 'FlexGrid',
  dataSchema: Schema.fromMap(flexGridSchema),
  widgetBuilder: (itemContext) {
    final Map<String, Object?> props = propsOf(itemContext);
    final Object? min = props['minItemWidth'];
    return SurfaceChildren(
      itemContext: itemContext,
      children: props['children'],
      builder: (context, children) => SiargaoFlexGrid(
        minItemWidth: min is num ? min.toDouble() : 280,
        children: children,
      ),
    );
  },
);

/// Marks a widget as a grid cell so components like `Heading` can render as
/// a compact tile instead of a page header.
class GridItemScope extends InheritedWidget {
  /// Creates a [GridItemScope].
  const GridItemScope({super.key, required super.child});

  /// Whether [context] is inside a grid cell.
  static bool isInGrid(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GridItemScope>() != null;

  @override
  bool updateShouldNotify(GridItemScope oldWidget) => false;
}

/// The Flutter widget behind `FlexGrid`.
class SiargaoFlexGrid extends StatelessWidget {
  /// Creates a [SiargaoFlexGrid].
  const SiargaoFlexGrid({
    super.key,
    required this.children,
    this.minItemWidth = 280,
    this.spacing = Gaps.xl,
  });

  /// Grid items in reading order.
  final List<Widget> children;

  /// Minimum column width.
  final double minItemWidth;

  /// Gap between items.
  final double spacing;

  /// Number of columns that fit [width].
  static int columnsFor(double width, double minItemWidth, double spacing) {
    final double min = math.max(120, minItemWidth);
    return math.max(1, ((width + spacing) / (min + spacing)).floor());
  }

  /// Spreads [count] items over as few rows as [maxColumns] allows, then
  /// evens the rows out, so 4 items on a 3 column width become 2 by 2
  /// instead of 3 plus 1.
  static int balancedColumns(int count, int maxColumns) {
    if (count <= 0) return 1;
    final int rows = (count / maxColumns).ceil();
    return math.max(1, (count / rows).ceil());
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final int used = balancedColumns(
          children.length,
          columnsFor(width, minItemWidth, spacing),
        );
        final double itemWidth = ((width - spacing * (used - 1)) / used)
            .floorToDouble();
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final Widget child in children)
              SizedBox(
                width: itemWidth,
                child: GridItemScope(child: child),
              ),
          ],
        );
      },
    );
  }
}
