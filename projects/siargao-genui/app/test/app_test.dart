import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:siargao_genui/app.dart';
import 'package:siargao_genui/config.dart';
import 'package:siargao_genui/deep_link.dart';
import 'package:siargao_genui/services/a2a_service.dart';
import 'package:siargao_genui/services/demo_backend.dart';
import 'package:siargao_genui/services/fixture_service.dart';
import 'package:siargao_genui/services/mcp_service.dart';

import 'support/test_harness.dart';

Future<void> settle(WidgetTester tester) async {
  // Fixture loading and mocked HTTP are real async work.
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> pumpApp(
  WidgetTester tester,
  Size size,
  DeepLink link, {
  DemoBackend? backend,
  AppConfig config = const AppConfig(),
}) async {
  setViewSize(tester, size);
  await tester.pumpWidget(
    SiargaoApp(
      config: config,
      link: link,
      backend:
          backend ?? OfflineBackend(FixtureService(bundle: DiskAssetBundle())),
    ),
  );
  await settle(tester);
}

Map<String, Object?> fixtureJson(String intent) =>
    (jsonDecode(File('../fixtures/$intent.json').readAsStringSync()) as Map)
        .cast<String, Object?>();

void main() {
  for (final Size size in const [Size(1440, 900), Size(390, 844)]) {
    for (final String view in const ['a2ui', 'text', 'both']) {
      testWidgets('chat $view renders at ${size.width}', (tester) async {
        await pumpApp(
          tester,
          size,
          DeepLink.fromUri(
            Uri.parse('/?tab=chat&intent=first_time_trip&view=$view'),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text('Plan my first trip to Siargao, 4 days, mid budget'),
          findsWidgets,
        );
        expect(find.text('A2A'), findsOneWidget);
        expect(find.text('0 model calls · template'), findsOneWidget);
        // Narrow screens fall back from both to A2UI.
        final bool showsA2ui = view == 'a2ui' || view == 'both';
        final bool showsText =
            view == 'text' || (view == 'both' && size.width >= 1100);
        expect(
          find.textContaining('Your first Siargao'),
          showsA2ui || showsText ? findsWidgets : findsNothing,
        );
        if (showsA2ui && showsText) {
          expect(find.text('Plain text'), findsOneWidget);
          expect(find.text('A2UI'), findsWidgets);
        }
      });
    }
    for (final String tab in const ['home', 'search', 'gallery']) {
      testWidgets('$tab renders at ${size.width}', (tester) async {
        await pumpApp(tester, size, DeepLink.fromUri(Uri.parse('/?tab=$tab')));
        expect(tester.takeException(), isNull);
        final String label = switch (tab) {
          'home' => 'MCP resource',
          'search' => 'MCP tool',
          _ => 'Static samples',
        };
        expect(find.text(label), findsOneWidget);
      });
    }
  }

  testWidgets('narrow screens use a NavigationBar, wide a NavigationRail', (
    tester,
  ) async {
    await pumpApp(tester, const Size(390, 844), const DeepLink());
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Offline'), findsOneWidget);
    await pumpApp(tester, const Size(1440, 900), const DeepLink());
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Offline fixtures'), findsOneWidget);
  });

  testWidgets('offline Choose shows a SnackBar with the action context', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const Size(1440, 2400),
      DeepLink.fromUri(Uri.parse('/?tab=search')),
    );
    await tester.tap(find.text('Choose').first);
    await settle(tester);
    expect(
      find.textContaining('Offline demo: "choose_stay" from stay-1'),
      findsOneWidget,
    );
    expect(find.textContaining('stayId: boardwalk-homestay'), findsOneWidget);
  });

  testWidgets('a chip sends its prompt and the toggle switches views', (
    tester,
  ) async {
    await pumpApp(tester, const Size(390, 844), const DeepLink());
    expect(find.text('Plan a Siargao trip'), findsOneWidget);
    await tester.ensureVisible(find.text('Surf this week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Surf this week'));
    await settle(tester);
    expect(find.text("How's the surf in Siargao this week?"), findsOneWidget);
    expect(find.byType(SegmentedButton<Object?>), findsNothing);
    await tester.tap(find.text('Text'));
    await settle(tester);
    expect(find.textContaining('surf', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live mode shows the model call count from the agent', (
    tester,
  ) async {
    final Map<String, Object?> fixture = fixtureJson('surf_this_week');
    final List<Map<String, Object?>> bodies = [];
    final MockClient agent = MockClient((request) async {
      final Map<String, Object?> body = (jsonDecode(request.body) as Map)
          .cast();
      bodies.add(body);
      final Map<Object?, Object?> meta =
          ((body['params']! as Map)['message']! as Map)['metadata']! as Map;
      final bool text = (meta['siargao']! as Map)['responseFormat'] == 'text';
      final Map<String, Object?> message = {
        'kind': 'message',
        'role': 'agent',
        'messageId': 'r',
        'parts': text
            ? [
                {'kind': 'text', 'text': fixture['text']},
              ]
            : [
                for (final Object? m in fixture['messages']! as List)
                  {'kind': 'data', 'data': m},
              ],
        'metadata': {
          'siargao': {
            'intent': 'surf_this_week',
            'source': 'model',
            'modelCalls': 1,
            'latencyMs': 900,
            'valid': true,
          },
        },
      };
      return http.Response(
        'data: ${jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': message})}\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final LiveBackend live = LiveBackend(
      a2a: A2aService(agentUrl: 'http://agent.test', client: agent),
      mcp: McpService(mcpUrl: 'http://mcp.test/mcp', client: agent),
    );
    await pumpApp(
      tester,
      const Size(1440, 900),
      DeepLink.fromUri(Uri.parse('/?intent=surf_this_week&view=both')),
      backend: live,
      config: const AppConfig(mode: DemoMode.live),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('1 model call · model'), findsOneWidget);
    expect(bodies, hasLength(2));
    final Set<Object?> formats = {
      for (final Map<String, Object?> b in bodies)
        ((((b['params']! as Map)['message']! as Map)['metadata']!
                as Map)['siargao']!
            as Map)['responseFormat'],
    };
    expect(formats, {'a2ui', 'text'});
    for (final Map<String, Object?> b in bodies) {
      final Map<Object?, Object?> siargao =
          ((((b['params']! as Map)['message']! as Map)['metadata']!
                  as Map)['siargao']!
              as Map);
      expect(siargao['intent'], 'surf_this_week');
    }
  });

  testWidgets('live errors render inline, never crash', (tester) async {
    final MockClient down = MockClient(
      (_) async => throw http.ClientException('Connection refused'),
    );
    final LiveBackend live = LiveBackend(
      a2a: A2aService(agentUrl: 'http://agent.test', client: down),
      mcp: McpService(mcpUrl: 'http://mcp.test/mcp', client: down),
    );
    await pumpApp(
      tester,
      const Size(1440, 900),
      DeepLink.fromUri(Uri.parse('/?tab=home')),
      backend: live,
      config: const AppConfig(mode: DemoMode.live),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('Could not reach the MCP server'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });
}
