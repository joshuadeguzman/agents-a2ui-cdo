import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:genui/genui.dart';
import 'package:intl/intl.dart';

/// Helpers to read component properties that are either a literal or a
/// `{"path": "/..."}` data binding, and to write two-way values back.

/// The data binding path of [raw], or null when [raw] is a literal.
String? bindingPath(Object? raw) {
  if (raw is Map && raw['path'] is String) return raw['path'] as String;
  return null;
}

/// The component properties as a map.
Map<String, Object?> propsOf(CatalogItemContext itemContext) {
  final Object data = itemContext.data;
  if (data is Map<String, Object?>) return data;
  if (data is Map) return data.cast<String, Object?>();
  return const <String, Object?>{};
}

/// Writes [value] to the data model when [raw] is a binding. Returns true when
/// it wrote something. Literals are not written (the caller keeps local state).
bool writeBinding(DataContext dataContext, Object? raw, Object? value) {
  final String? path = bindingPath(raw);
  if (path == null) return false;
  dataContext.update(DataPath(path), value);
  return true;
}

/// Resolved values for a set of raw properties.
@immutable
class Resolved {
  /// Wraps resolved values.
  const Resolved(this._values);

  final Map<String, Object?> _values;

  /// Raw resolved value.
  Object? operator [](String key) => _values[key];

  /// A string, or null when missing or empty.
  String? string(String key) {
    final Object? v = _values[key];
    if (v == null) return null;
    final String s = v is String ? v : v.toString();
    return s.trim().isEmpty ? null : s;
  }

  /// A number, or null.
  num? number(String key) {
    final Object? v = _values[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  /// A list of maps (for timeline items, cost lines and buttons).
  List<Map<String, Object?>> maps(String key) {
    final Object? v = _values[key];
    if (v is! List) return const [];
    return [
      for (final Object? e in v)
        if (e is Map) e.cast<String, Object?>(),
    ];
  }

  /// A list of strings.
  List<String> strings(String key) {
    final Object? v = _values[key];
    if (v is! List) return const [];
    return [
      for (final Object? e in v)
        if (e != null) e.toString(),
    ];
  }
}

/// Resolves several literal-or-bound properties at once and rebuilds when any
/// bound value changes in the data model.
class BoundProps extends StatefulWidget {
  /// Creates a [BoundProps].
  const BoundProps({
    super.key,
    required this.dataContext,
    required this.props,
    required this.builder,
  });

  /// Context used to resolve bindings.
  final DataContext dataContext;

  /// Raw property values keyed by name.
  final Map<String, Object?> props;

  /// Builds the widget from resolved values.
  final Widget Function(BuildContext context, Resolved values) builder;

  @override
  State<BoundProps> createState() => _BoundPropsState();
}

class _BoundPropsState extends State<BoundProps> {
  static const DeepCollectionEquality _eq = DeepCollectionEquality();
  final Map<String, ValueListenable<Object?>> _listenables = {};
  Listenable? _merged;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(BoundProps oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataContext != widget.dataContext ||
        !_eq.equals(oldWidget.props, widget.props)) {
      _unsubscribe();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _subscribe() {
    for (final MapEntry<String, Object?> e in widget.props.entries) {
      final String? path = bindingPath(e.value);
      if (path != null) {
        _listenables[e.key] = widget.dataContext.subscribe<Object?>(
          DataPath(path),
        );
      }
    }
    _merged = Listenable.merge(_listenables.values.toList());
  }

  void _unsubscribe() {
    for (final ValueListenable<Object?> l in _listenables.values) {
      if (l is ChangeNotifier) (l as ChangeNotifier).dispose();
    }
    _listenables.clear();
    _merged = null;
  }

  Resolved _resolve() {
    final Map<String, Object?> out = {};
    for (final MapEntry<String, Object?> e in widget.props.entries) {
      final ValueListenable<Object?>? l = _listenables[e.key];
      out[e.key] = l != null ? l.value : e.value;
    }
    return Resolved(out);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _merged!,
      builder: (context, _) => widget.builder(context, _resolve()),
    );
  }
}

/// Dispatches an A2UI `action` (`{"event": {"name", "context"}}`) from a
/// component. Context values may be bindings; they are resolved first.
Future<void> dispatchAction(
  CatalogItemContext itemContext,
  Object? action,
) async {
  if (action is! Map) return;
  final Object? event = action['event'];
  if (event is! Map) return;
  final Object? name = event['name'];
  if (name is! String || name.isEmpty) return;
  final Object? rawContext = event['context'];
  final Map<String, Object?> resolved = rawContext is Map
      ? await resolveContext(
          itemContext.dataContext,
          rawContext.cast<String, Object?>(),
        )
      : <String, Object?>{};
  itemContext.dispatchEvent(
    UserActionEvent(
      name: name,
      sourceComponentId: itemContext.id,
      context: resolved,
    ),
  );
}

final NumberFormat _grouped = NumberFormat.decimalPattern('en_US');

/// Formats an amount like `PHP 4,500`. The bundled font has no peso sign, and
/// the ISO code reads well on a projector.
String formatMoney(num amount, {String? currency}) {
  final String code = (currency == null || currency.trim().isEmpty)
      ? 'PHP'
      : currency.trim().toUpperCase();
  final String n = amount % 1 == 0
      ? _grouped.format(amount.round())
      : NumberFormat('#,##0.00', 'en_US').format(amount);
  return '$code $n';
}

/// Joins the last two words with a non-breaking space so a wrapped heading or
/// button never leaves a single word alone on its last line.
String noWidow(String text) {
  final String t = text.trim();
  final int i = t.lastIndexOf(' ');
  if (i <= 0) return t;
  final String head = t.substring(0, i);
  final String tail = t.substring(i + 1);
  // Only glue short tails; gluing long words can force awkward breaks.
  if (tail.length > 12 || !head.contains(' ')) return t;
  return '$head $tail';
}
