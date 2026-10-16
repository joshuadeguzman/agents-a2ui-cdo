import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:siargao_genui/a2ui/surface_session.dart';
import 'package:siargao_genui/services/fixture_service.dart';

import '../support/test_harness.dart';

/// Every fixture in ../fixtures renders through a real SurfaceController
/// with no exception, no fallback widget and no validation error.
void main() {
  final List<File> files =
      Directory('../fixtures')
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.json') && !f.path.endsWith('_dataset.json'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('all six intents have a fixture', () {
    expect(
      files.map((f) => f.uri.pathSegments.last.replaceAll('.json', '')).toSet(),
      FixtureService.intents.toSet(),
    );
  });

  for (final File file in files) {
    for (final double width in const [1180, 358]) {
      final String name = file.uri.pathSegments.last;
      testWidgets('$name renders cleanly at $width', (tester) async {
        final Fixture fixture = Fixture.fromJson(
          (readJsonFile(file.path)! as Map).cast<String, Object?>(),
        );
        final SurfaceSession session = await pumpSurface(
          tester,
          fixture.messages,
          width: width,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();

        expect(session.surfaceId, fixture.intent);
        expect(tester.takeException(), isNull);
        expect(find.byType(FallbackWidget), findsNothing);
        expect(session.skipped, isEmpty);
        expect(
          session.errors.value,
          isEmpty,
          reason: session.errors.value.join('\n'),
        );
        // The surface rendered real content: at least one Text from the data.
        expect(find.byType(Text), findsWidgets);
      });
    }
  }
}
