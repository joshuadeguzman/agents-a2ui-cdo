import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../theme/app_theme.dart';
import 'binding.dart';
import 'catalog_schemas.g.dart';

/// `ChipRow`: single or multi select chips bound to a string array.
final CatalogItem chipRowItem = CatalogItem(
  name: 'ChipRow',
  dataSchema: Schema.fromMap(chipRowSchema),
  widgetBuilder: (itemContext) {
    final Map<String, Object?> props = propsOf(itemContext);
    final Object? rawSelected = props['selected'];
    return BoundProps(
      dataContext: itemContext.dataContext,
      props: {
        'label': props['label'],
        'options': props['options'],
        'selected': rawSelected,
      },
      builder: (context, v) => ChipRowView(
        label: v.string('label'),
        options: v.strings('options'),
        selected: v.strings('selected'),
        multiSelect: props['multiSelect'] == true,
        bound: bindingPath(rawSelected) != null,
        onChanged: (next) =>
            writeBinding(itemContext.dataContext, rawSelected, next),
      ),
    );
  },
);

/// The Flutter widget behind `ChipRow`.
class ChipRowView extends StatefulWidget {
  /// Creates a [ChipRowView].
  const ChipRowView({
    super.key,
    required this.options,
    required this.selected,
    this.label,
    this.multiSelect = false,
    this.bound = false,
    this.onChanged,
  });

  /// Optional label above the chips.
  final String? label;

  /// Chip labels.
  final List<String> options;

  /// Selected chip labels.
  final List<String> selected;

  /// Whether several chips can be selected.
  final bool multiSelect;

  /// Whether the selection is a data binding.
  final bool bound;

  /// Called with the new selection.
  final ValueChanged<List<String>>? onChanged;

  @override
  State<ChipRowView> createState() => _ChipRowViewState();
}

class _ChipRowViewState extends State<ChipRowView> {
  List<String>? _local;

  List<String> get _selected =>
      widget.bound ? widget.selected : (_local ?? widget.selected);

  void _toggle(String option) {
    final List<String> current = _selected;
    final List<String> next;
    if (widget.multiSelect) {
      next = current.contains(option)
          ? [
              for (final String s in current)
                if (s != option) s,
            ]
          : [
              // Keep the option order stable.
              for (final String o in widget.options)
                if (o == option || current.contains(o)) o,
            ];
    } else {
      next = current.length == 1 && current.first == option
          ? <String>[]
          : <String>[option];
    }
    if (!widget.bound) setState(() => _local = next);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final List<String> selected = _selected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: t.titleMedium),
          const SizedBox(height: Gaps.md),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final String option in widget.options)
              widget.multiSelect
                  ? FilterChip(
                      label: Text(option),
                      selected: selected.contains(option),
                      onSelected: (_) => _toggle(option),
                    )
                  : ChoiceChip(
                      label: Text(option),
                      selected: selected.contains(option),
                      onSelected: (_) => _toggle(option),
                    ),
          ],
        ),
      ],
    );
  }
}
