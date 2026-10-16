import 'package:flutter/widgets.dart';
import 'package:genui/genui.dart';

import 'binding.dart';

/// True when [id] names a component that exists and whose type is in the
/// catalog. Containers use this to skip unknown or missing children so one
/// bad component never takes down its siblings.
bool isRenderableChild(CatalogItemContext itemContext, String id) {
  final Component? component = itemContext.getComponent(id);
  if (component == null) {
    debugPrint('Skipping child "$id": no such component.');
    return false;
  }
  if (itemContext.getCatalogItem(component.type) == null) {
    debugPrint('Skipping child "$id": unknown type "${component.type}".');
    return false;
  }
  return true;
}

/// Builds the children of a container from an A2UI `ChildList`: either a list
/// of ids, or a template `{"path": "/list", "componentId": "card"}`.
class SurfaceChildren extends StatelessWidget {
  /// Creates a [SurfaceChildren].
  const SurfaceChildren({
    super.key,
    required this.itemContext,
    required this.children,
    required this.builder,
  });

  /// The parent's item context.
  final CatalogItemContext itemContext;

  /// The raw `children` property.
  final Object? children;

  /// Lays out the built children.
  final Widget Function(BuildContext context, List<Widget> children) builder;

  @override
  Widget build(BuildContext context) {
    final Object? raw = children;
    if (raw is List) {
      final List<Widget> built = [
        for (final Object? id in raw)
          if (id is String && isRenderableChild(itemContext, id))
            itemContext.buildChild(id),
      ];
      return builder(context, built);
    }
    if (raw is Map && raw['path'] is String && raw['componentId'] is String) {
      final String path = raw['path'] as String;
      final String componentId = raw['componentId'] as String;
      if (!isRenderableChild(itemContext, componentId)) {
        return builder(context, const []);
      }
      return BoundProps(
        dataContext: itemContext.dataContext,
        props: {
          'list': {'path': path},
        },
        builder: (context, values) {
          final Object? list = values['list'];
          final int count = list is List ? list.length : 0;
          return builder(context, [
            for (var i = 0; i < count; i++)
              KeyedSubtree(
                key: ValueKey('$componentId-$i'),
                child: itemContext.buildChild(
                  componentId,
                  itemContext.dataContext.nested(DataPath('$path/$i')),
                ),
              ),
          ]);
        },
      );
    }
    return builder(context, const []);
  }
}

/// Limits a component to a readable width inside a wide surface.
class ReadableWidth extends StatelessWidget {
  /// Creates a [ReadableWidth].
  const ReadableWidth({super.key, required this.child, this.maxWidth = 760});

  /// The constrained child.
  final Widget child;

  /// Maximum width in logical pixels.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
