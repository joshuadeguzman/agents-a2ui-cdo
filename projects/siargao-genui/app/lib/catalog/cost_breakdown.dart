import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../theme/app_theme.dart';
import 'binding.dart';
import 'catalog_schemas.g.dart';
import 'children.dart';

/// One cost line.
@immutable
class CostLine {
  /// Creates a [CostLine].
  const CostLine(this.label, this.amount);

  /// Reads a line from a JSON map. Missing amounts count as zero.
  factory CostLine.fromMap(Map<String, Object?> m) {
    final Object? a = m['amount'];
    return CostLine(
      m['label']?.toString() ?? '',
      a is num ? a : num.tryParse(a?.toString() ?? '') ?? 0,
    );
  }

  /// What the cost is for.
  final String label;

  /// Amount in the table currency.
  final num amount;
}

/// `CostBreakdown`: cost lines plus a computed total.
final CatalogItem costBreakdownItem = CatalogItem(
  name: 'CostBreakdown',
  dataSchema: Schema.fromMap(costBreakdownSchema),
  widgetBuilder: (itemContext) {
    final Map<String, Object?> props = propsOf(itemContext);
    return BoundProps(
      dataContext: itemContext.dataContext,
      props: {
        'title': props['title'],
        'currency': props['currency'],
        'items': props['items'],
        'totalLabel': props['totalLabel'],
      },
      builder: (context, v) => CostBreakdownCard(
        title: v.string('title') ?? '',
        currency: v.string('currency') ?? 'PHP',
        totalLabel: v.string('totalLabel') ?? 'Total',
        lines: v.maps('items').map(CostLine.fromMap).toList(),
      ),
    );
  },
);

/// The Flutter widget behind `CostBreakdown`.
class CostBreakdownCard extends StatelessWidget {
  /// Creates a [CostBreakdownCard].
  const CostBreakdownCard({
    super.key,
    required this.title,
    required this.lines,
    this.currency = 'PHP',
    this.totalLabel = 'Total',
  });

  /// Table heading.
  final String title;

  /// Cost lines.
  final List<CostLine> lines;

  /// ISO currency code.
  final String currency;

  /// Label of the computed total row.
  final String totalLabel;

  /// Sum of all lines.
  num get total => lines.fold<num>(0, (sum, l) => sum + l.amount);

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    const List<FontFeature> tabular = [FontFeature.tabularFigures()];
    return ReadableWidth(
      maxWidth: 820,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(noWidow(title), style: t.titleLarge),
              const SizedBox(height: Gaps.md),
              for (final CostLine line in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(line.label, style: t.bodyLarge)),
                      const SizedBox(width: Gaps.lg),
                      Text(
                        formatMoney(line.amount, currency: currency),
                        style: t.bodyLarge?.copyWith(fontFeatures: tabular),
                      ),
                    ],
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Gaps.sm),
                child: Divider(height: 1),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: Text(totalLabel, style: t.titleMedium)),
                  const SizedBox(width: Gaps.lg),
                  Text(
                    formatMoney(total, currency: currency),
                    style: t.titleLarge?.copyWith(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
