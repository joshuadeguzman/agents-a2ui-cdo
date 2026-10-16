import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app bundles copies of ../fixtures/*.json and ../catalog/images.json.
/// Run tool/sync_shared.sh when this fails.
void main() {
  const String hint = 'Out of sync. Run tool/sync_shared.sh.';

  test('every shared fixture is copied byte for byte', () {
    final List<File> sources = Directory('../fixtures')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(sources, isNotEmpty);
    for (final File src in sources) {
      final String name = src.uri.pathSegments.last;
      final File copy = File('assets/fixtures/$name');
      expect(copy.existsSync(), isTrue, reason: '$name missing. $hint');
      expect(
        copy.readAsStringSync(),
        src.readAsStringSync(),
        reason: '$name differs. $hint',
      );
    }
    final Set<String> sourceNames = {
      for (final File f in sources) f.uri.pathSegments.last,
    };
    final List<String> extra = Directory('assets/fixtures')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.json') && !sourceNames.contains(n))
        .toList();
    expect(extra, isEmpty, reason: 'Stale copies $extra. $hint');
  });

  test('images.json is copied byte for byte', () {
    expect(
      File('assets/catalog/images.json').readAsStringSync(),
      File('../catalog/images.json').readAsStringSync(),
      reason: hint,
    );
  });
}
