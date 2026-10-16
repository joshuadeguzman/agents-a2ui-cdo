import 'dart:convert';

/// Result of [sanitizeMessages].
class SanitizeResult {
  /// Creates a [SanitizeResult].
  const SanitizeResult(this.messages, this.skipped);

  /// Messages safe to hand to genui.
  final List<Map<String, Object?>> messages;

  /// `id: type` of every component that was dropped.
  final List<String> skipped;
}

/// Drops components whose type is not in [knownTypes] from every
/// `updateComponents` message, and removes their ids from the `children`
/// lists of the components that stay.
///
/// genui's `Catalog.buildWidget` throws for an unknown type; the `Surface`
/// then shows a red fallback box and reports a validation error. Removing
/// unknown components before `handleMessage` keeps the surface clean, and the
/// rest of it renders as if the unknown component was never sent.
///
/// The input is not modified. Messages that are not maps are dropped.
SanitizeResult sanitizeMessages(
  List<Object?> messages,
  Set<String> knownTypes,
) {
  final List<Map<String, Object?>> out = [];
  final List<String> skipped = [];
  for (final Object? message in messages) {
    if (message is! Map) continue;
    final Map<String, Object?> copy = _deepCopy(message);
    final Object? update = copy['updateComponents'];
    if (update is Map<String, Object?> && update['components'] is List) {
      final List<Object?> components = update['components'] as List<Object?>;
      final Set<String> dropped = {};
      final List<Map<String, Object?>> kept = [];
      for (final Object? c in components) {
        if (c is! Map<String, Object?>) continue;
        final Object? type = c['component'];
        final Object? id = c['id'];
        if (type is String && knownTypes.contains(type)) {
          kept.add(c);
        } else {
          if (id is String) dropped.add(id);
          skipped.add('$id: $type');
        }
      }
      for (final Map<String, Object?> c in kept) {
        final Object? children = c['children'];
        if (children is List && dropped.isNotEmpty) {
          c['children'] = [
            for (final Object? child in children)
              if (!(child is String && dropped.contains(child))) child,
          ];
        }
      }
      update['components'] = kept;
    }
    out.add(copy);
  }
  return SanitizeResult(out, skipped);
}

Map<String, Object?> _deepCopy(Map<Object?, Object?> m) =>
    (jsonDecode(jsonEncode(m)) as Map).cast<String, Object?>();
