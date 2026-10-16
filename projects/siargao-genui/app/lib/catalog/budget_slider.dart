import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../theme/app_theme.dart';
import 'binding.dart';
import 'catalog_schemas.g.dart';
import 'children.dart';

/// `BudgetSlider`: two-way budget input bound to a data model number.
final CatalogItem budgetSliderItem = CatalogItem(
  name: 'BudgetSlider',
  dataSchema: Schema.fromMap(budgetSliderSchema),
  widgetBuilder: (itemContext) {
    final Map<String, Object?> props = propsOf(itemContext);
    final Object? rawValue = props['value'];
    final num min = _num(props['min']) ?? 0;
    final num max = _num(props['max']) ?? 10000;
    final num step = _num(props['step']) ?? 100;
    return BoundProps(
      dataContext: itemContext.dataContext,
      props: {
        'label': props['label'],
        'value': rawValue,
        'currency': props['currency'],
      },
      builder: (context, v) => BudgetSliderView(
        label: v.string('label') ?? '',
        min: min,
        max: max,
        step: step,
        currency: v.string('currency') ?? 'PHP',
        value: v.number('value'),
        bound: bindingPath(rawValue) != null,
        onChanged: (value) =>
            writeBinding(itemContext.dataContext, rawValue, value),
      ),
    );
  },
);

num? _num(Object? v) => v is num ? v : num.tryParse(v?.toString() ?? '');

/// The Flutter widget behind `BudgetSlider`.
///
/// When [bound] is true the data model owns the value and [onChanged] writes
/// it back. Otherwise the widget keeps the value locally.
class BudgetSliderView extends StatefulWidget {
  /// Creates a [BudgetSliderView].
  const BudgetSliderView({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    this.step = 100,
    this.value,
    this.currency = 'PHP',
    this.bound = false,
    this.onChanged,
  });

  /// What the amount means.
  final String label;

  /// Lowest amount.
  final num min;

  /// Highest amount.
  final num max;

  /// Increment.
  final num step;

  /// Current amount from the data model or a literal.
  final num? value;

  /// ISO currency code.
  final String currency;

  /// Whether the value is a data binding.
  final bool bound;

  /// Called with the new amount.
  final ValueChanged<num>? onChanged;

  @override
  State<BudgetSliderView> createState() => _BudgetSliderViewState();
}

class _BudgetSliderViewState extends State<BudgetSliderView> {
  num? _local;

  num get _lo => math.min(widget.min, widget.max);
  num get _hi => math.max(widget.min, widget.max);

  num _snap(double raw) {
    final num step = widget.step > 0 ? widget.step : 1;
    final num snapped = _lo + ((raw - _lo) / step).round() * step;
    final num clamped = snapped.clamp(_lo, _hi);
    return clamped % 1 == 0 ? clamped.toInt() : clamped;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final num current =
        (widget.bound ? widget.value : (_local ?? widget.value))?.clamp(
          _lo,
          _hi,
        ) ??
        _lo;
    final num range = _hi - _lo;
    final int? divisions = (widget.step > 0 && range > 0)
        ? (range / widget.step).round()
        : null;
    return ReadableWidth(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Gaps.lg,
                runSpacing: Gaps.xs,
                children: [
                  Text(widget.label, style: t.titleMedium),
                  Text(
                    formatMoney(current, currency: widget.currency),
                    style: t.titleLarge?.copyWith(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gaps.xs),
              Slider(
                value: current.toDouble(),
                min: _lo.toDouble(),
                max: range > 0 ? _hi.toDouble() : _lo.toDouble() + 1,
                divisions:
                    (divisions != null && divisions > 0 && divisions <= 1000)
                    ? divisions
                    : null,
                label: formatMoney(current, currency: widget.currency),
                semanticFormatterCallback: (v) =>
                    formatMoney(_snap(v), currency: widget.currency),
                onChanged: (raw) {
                  final num next = _snap(raw);
                  if (!widget.bound) setState(() => _local = next);
                  widget.onChanged?.call(next);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatMoney(_lo, currency: widget.currency),
                      style: t.bodySmall?.copyWith(color: AppColors.inkMuted),
                    ),
                    Text(
                      formatMoney(_hi, currency: widget.currency),
                      style: t.bodySmall?.copyWith(color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
