import 'package:a2ui_core/a2ui_core.dart' as core;
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:siargao_genui/a2ui/surface_sanitizer.dart';
import 'package:siargao_genui/a2ui/surface_session.dart';
import 'package:siargao_genui/catalog/siargao_catalog.dart';

import '../support/test_harness.dart';

List<Map<String, Object?>> withUnknown() => surfaceMessages('s', [
  {
    'id': 'root',
    'component': 'Stack',
    'children': ['before', 'mystery', 'grid', 'after'],
  },
  {'id': 'before', 'component': 'Heading', 'title': 'Before the unknown'},
  {'id': 'mystery', 'component': 'Carousel3D', 'speed': 9000},
  {
    'id': 'grid',
    'component': 'FlexGrid',
    'children': ['tile', 'video', 'ghost'],
  },
  {'id': 'tile', 'component': 'Heading', 'title': 'Grid sibling'},
  {'id': 'video', 'component': 'Video', 'url': 'https://example.com/v.mp4'},
  {'id': 'after', 'component': 'Heading', 'title': 'After the unknown'},
]);

Future<void> settleValidation(WidgetTester tester) async {
  // genui validates components asynchronously after updateComponents.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('sanitizer drops unknown components and prunes children', () {
    final List<Map<String, Object?>> input = withUnknown();
    final SanitizeResult r = sanitizeMessages(input, siargaoComponentNames);
    expect(r.skipped, ['mystery: Carousel3D', 'video: Video']);
    final List<Object?> components =
        (r.messages[1]['updateComponents']! as Map)['components']! as List;
    final List<Object?> ids = components.map((c) => (c! as Map)['id']).toList();
    expect(ids, ['root', 'before', 'grid', 'tile', 'after']);
    expect((components[0]! as Map)['children'], ['before', 'grid', 'after']);
    // A dangling id that was never sent stays; the container skips it.
    expect((components[2]! as Map)['children'], ['tile', 'ghost']);
    // The input is not modified.
    expect(
      ((input[1]['updateComponents']! as Map)['components']! as List).length,
      7,
    );
  });

  testWidgets('unknown components are skipped and siblings still render', (
    tester,
  ) async {
    final SurfaceSession session = await pumpSurface(tester, withUnknown());
    await settleValidation(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Before the'), findsOneWidget);
    expect(find.text('Grid sibling'), findsOneWidget);
    expect(find.textContaining('After the'), findsOneWidget);
    expect(find.byType(FallbackWidget), findsNothing);
    expect(session.skipped, hasLength(2));
    expect(session.errors.value, isEmpty);
  });

  testWidgets('a container skips an unknown child that bypassed sanitizing', (
    tester,
  ) async {
    final SurfaceSession session = SurfaceSession();
    addTearDown(session.dispose);
    session.apply(
      surfaceMessages('s', [
        {
          'id': 'root',
          'component': 'Stack',
          'children': ['ok', 'later', 'missing'],
        },
        {'id': 'ok', 'component': 'Heading', 'title': 'Still here'},
      ]),
    );
    // Straight to the controller, skipping the sanitizer, to prove the
    // second layer: containers check each child against the catalog.
    session.controller.handleMessage(
      core.A2uiMessage.fromJson({
        'version': 'v0.9',
        'updateComponents': {
          'surfaceId': 's',
          'components': [
            {'id': 'later', 'component': 'Mystery', 'x': 1},
          ],
        },
      }),
    );
    await tester.pumpWidget(themed(Surface(surfaceContext: session.context!)));
    await settleValidation(tester);

    expect(find.text('Still here'), findsOneWidget);
    expect(find.byType(FallbackWidget), findsNothing);
    expect(tester.takeException(), isNull);
    // genui reports the unknown type; the session keeps it local.
    expect(session.errors.value.join(), contains('Mystery'));
  });

  testWidgets('renderer errors are recorded locally, never auto-sent', (
    tester,
  ) async {
    final SurfaceSession session = SurfaceSession();
    addTearDown(session.dispose);
    // Heading without its required title fails schema validation.
    session.apply(
      surfaceMessages('s', [
        {
          'id': 'root',
          'component': 'Stack',
          'children': ['bad', 'good'],
        },
        {'id': 'bad', 'component': 'Heading'},
        {'id': 'good', 'component': 'Heading', 'title': 'Good one'},
      ]),
    );
    await tester.pumpWidget(themed(Surface(surfaceContext: session.context!)));
    await settleValidation(tester);
    expect(find.text('Good one'), findsOneWidget);
    expect(session.errors.value, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
