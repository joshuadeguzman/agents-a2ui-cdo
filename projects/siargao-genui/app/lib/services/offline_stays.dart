import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'fixture_service.dart';

/// Arguments of the `search_stays` MCP tool.
@immutable
class StayQuery {
  /// Creates a [StayQuery].
  const StayQuery({
    required this.area,
    required this.nights,
    required this.maxPrice,
  });

  /// The query recorded in `fixtures/stays_near_cloud9.json`.
  static const StayQuery fixtureDefault = StayQuery(
    area: 'Cloud 9',
    nights: 3,
    maxPrice: 4500,
  );

  /// Area, matched ignoring case.
  final String area;

  /// Nights (carried into the surface, does not filter).
  final int nights;

  /// Max price per night in PHP.
  final int maxPrice;

  /// Tool arguments.
  Map<String, Object?> toArguments() => {
    'area': area,
    'nights': nights,
    'max_price': maxPrice,
  };

  @override
  bool operator ==(Object other) =>
      other is StayQuery &&
      other.area.toLowerCase() == area.toLowerCase() &&
      other.nights == nights &&
      other.maxPrice == maxPrice;

  @override
  int get hashCode => Object.hash(area.toLowerCase(), nights, maxPrice);
}

/// The `search_stays` filter from fixtures/README.md: same area ignoring
/// case, price at most `max_price`, sorted by price then id, at most 4.
List<Stay> filterStays(List<Stay> stays, StayQuery q) {
  final List<Stay> hits =
      stays
          .where(
            (s) =>
                s.area.toLowerCase() == q.area.trim().toLowerCase() &&
                s.pricePerNight <= q.maxPrice,
          )
          .toList()
        ..sort((a, b) {
          final int byPrice = a.pricePerNight.compareTo(b.pricePerNight);
          return byPrice != 0 ? byPrice : a.id.compareTo(b.id);
        });
  return hits.take(4).toList();
}

/// Rebuilds the `stays_near_cloud9` template for another query, the way the
/// MCP tool does: keep the components, swap the data model, and keep one
/// StayCard per result. Used offline when the form differs from the fixture.
List<Map<String, Object?>> buildStaysMessages(
  Fixture template,
  List<Stay> results,
  StayQuery q,
) {
  final List<Map<String, Object?>> messages = [
    for (final Map<String, Object?> m in template.messages)
      (jsonDecode(jsonEncode(m)) as Map).cast<String, Object?>(),
  ];
  final String price = NumberFormat.decimalPattern('en_US').format(q.maxPrice);
  final String nights = '${q.nights} night${q.nights == 1 ? '' : 's'}';
  for (final Map<String, Object?> m in messages) {
    final Object? uc = m['updateComponents'];
    if (uc is Map) {
      final List<Object?> components = uc['components'] as List<Object?>;
      final List<Object?> kept = [];
      for (final Object? c in components) {
        if (c is! Map) continue;
        final Object? id = c['id'];
        if (id is String && id.startsWith('stay-')) {
          final int index = (int.tryParse(id.substring(5)) ?? 1) - 1;
          if (index >= results.length) continue;
          final Object? action = c['action'];
          if (action is Map && action['event'] is Map) {
            (action['event'] as Map)['context'] = {
              'stayId': results[index].id,
              'nights': q.nights,
            };
          }
        }
        if (id == 'stays-grid') {
          c['children'] = [
            for (var i = 0; i < results.length; i++) 'stay-${i + 1}',
          ];
        }
        if (id == 'root' && results.isEmpty) {
          c['children'] = [
            for (final Object? child in c['children'] as List<Object?>)
              if (child != 'stays-grid') child,
          ];
        }
        if (id == 'stays-grid' && results.isEmpty) continue;
        kept.add(c);
      }
      uc['components'] = kept;
    }
    final Object? udm = m['updateDataModel'];
    if (udm is Map && udm['value'] is Map) {
      final Map<Object?, Object?> value = udm['value'] as Map;
      value['query'] = q.toArguments();
      value['stays'] = [for (final Stay s in results) s.toJson()];
      value['hero'] = {
        'eyebrow': '$nights, up to PHP $price per night',
        'title': results.isEmpty
            ? 'No stays in ${q.area} under PHP $price'
            : '${results.length} '
                  'stay${results.length == 1 ? '' : 's'} near ${q.area}',
        'subtitle': results.isEmpty
            ? 'Try a higher price or another area.'
            : 'Sample prices per night, cheapest first.',
      };
    }
  }
  return messages;
}
