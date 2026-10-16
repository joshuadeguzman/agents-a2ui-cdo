import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../theme/app_theme.dart';
import 'binding.dart';
import 'catalog_schemas.g.dart';

/// One next-step button.
@immutable
class ActionButtonSpec {
  /// Creates an [ActionButtonSpec].
  const ActionButtonSpec({
    required this.label,
    this.style = 'secondary',
    this.action,
  });

  /// Reads a button from a JSON map.
  factory ActionButtonSpec.fromMap(Map<String, Object?> m) => ActionButtonSpec(
    label: m['label']?.toString() ?? '',
    style: m['style']?.toString() ?? 'secondary',
    action: m['action'],
  );

  /// Button text.
  final String label;

  /// `primary`, `secondary` or `text`.
  final String style;

  /// The raw A2UI action.
  final Object? action;
}

/// `Actions`: a row of next-step buttons.
final CatalogItem actionsItem = CatalogItem(
  name: 'Actions',
  dataSchema: Schema.fromMap(actionsSchema),
  widgetBuilder: (itemContext) {
    final Map<String, Object?> props = propsOf(itemContext);
    return BoundProps(
      dataContext: itemContext.dataContext,
      props: {'buttons': props['buttons']},
      builder: (context, v) => ActionsRow(
        buttons: v.maps('buttons').map(ActionButtonSpec.fromMap).toList(),
        onPressed: (button) => dispatchAction(itemContext, button.action),
      ),
    );
  },
);

/// The Flutter widget behind `Actions`.
class ActionsRow extends StatelessWidget {
  /// Creates an [ActionsRow].
  const ActionsRow({super.key, required this.buttons, this.onPressed});

  /// Buttons, left to right.
  final List<ActionButtonSpec> buttons;

  /// Called when a button is pressed.
  final void Function(ActionButtonSpec button)? onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Gaps.md,
      runSpacing: Gaps.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final ActionButtonSpec b in buttons)
          switch (b.style) {
            'primary' => FilledButton(
              onPressed: () => onPressed?.call(b),
              child: Text(noWidow(b.label)),
            ),
            'text' => TextButton(
              onPressed: () => onPressed?.call(b),
              child: Text(noWidow(b.label)),
            ),
            _ => OutlinedButton(
              onPressed: () => onPressed?.call(b),
              child: Text(noWidow(b.label)),
            ),
          },
      ],
    );
  }
}
