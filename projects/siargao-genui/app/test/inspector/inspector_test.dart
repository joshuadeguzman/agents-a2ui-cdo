import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:siargao_genui/app.dart';
import 'package:siargao_genui/config.dart';
import 'package:siargao_genui/deep_link.dart';
import 'package:siargao_genui/inspector/inspector_panel.dart';
import 'package:siargao_genui/inspector/wire_log.dart';
import 'package:siargao_genui/services/a2a_service.dart';
import 'package:siargao_genui/services/demo_backend.dart';
import 'package:siargao_genui/services/fixture_service.dart';
import 'package:siargao_genui/services/models.dart';

import '../services/a2a_service_test.dart'
    show agentMessage, sse, threeMessages;
import '../support/test_harness.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<WireLog> pumpInspected(
  WidgetTester tester,
  String query, {
  Size size = const Size(1440, 900),
}) async {
  final DeepLink link = DeepLink.fromUri(Uri.parse('/?$query'));
  final WireLog wire = WireLog(
    open: link.inspect,
    pace: link.pace ?? RenderPace.instant,
  );
  addTearDown(wire.dispose);
  setViewSize(tester, size);
  await tester.pumpWidget(
    SiargaoApp(
      config: const AppConfig(),
      link: link,
      wire: wire,
      backend: OfflineBackend(
        FixtureService(bundle: DiskAssetBundle()),
        wire: wire,
      ),
    ),
  );
  await settle(tester);
  return wire;
}

void main() {
  testWidgets('lists the request and each A2UI message as rendered', (
    tester,
  ) async {
    final WireLog wire = await pumpInspected(
      tester,
      'tab=chat&intent=first_time_trip&view=a2ui&inspect=1',
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(InspectorPanel), findsOneWidget);
    expect(find.text('A2UI stream'), findsOneWidget);
    for (final String type in const [
      'createSurface',
      'updateComponents',
      'updateDataModel',
    ]) {
      expect(find.text(type), findsOneWidget);
    }
    expect(find.text('3/3 rendered'), findsOneWidget);
    // The plain text half is logged but hidden by default.
    expect(wire.traces.where((t) => t.textOnly), hasLength(1));
    expect(find.text('text answer'), findsNothing);
  });

  testWidgets('step mode renders one message per click', (tester) async {
    await pumpInspected(
      tester,
      'tab=chat&intent=first_time_trip&view=a2ui&inspect=1&pace=step',
    );
    expect(find.text('Waiting for createSurface'), findsOneWidget);
    expect(find.text('0/3 rendered'), findsOneWidget);
    expect(find.text('Next: createSurface'), findsOneWidget);

    await tester.tap(find.text('Render next'));
    await settle(tester);
    expect(find.text('Surface created. No components yet.'), findsOneWidget);

    await tester.tap(find.text('Render next'));
    await settle(tester);
    await tester.tap(find.text('Render next'));
    await settle(tester);
    expect(find.text('3/3 rendered'), findsOneWidget);
    expect(find.text('Applied all 3 A2UI messages'), findsOneWidget);
    expect(find.textContaining('Your first Siargao'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the panel finishes a paused surface', (tester) async {
    final WireLog wire = await pumpInspected(
      tester,
      'tab=chat&intent=first_time_trip&view=a2ui&inspect=1&pace=step',
    );
    expect(wire.canStep, isTrue);
    await tester.tap(find.byTooltip('Close the inspector'));
    await settle(tester);
    expect(find.byType(InspectorPanel), findsNothing);
    expect(find.textContaining('Your first Siargao'), findsWidgets);
  });

  testWidgets('toggling the panel keeps the chat and does not resend', (
    tester,
  ) async {
    final WireLog wire = await pumpInspected(
      tester,
      'tab=chat&intent=first_time_trip&view=a2ui',
      size: const Size(390, 844),
    );
    final int traces = wire.traces.length;
    expect(find.byType(InspectorPanel), findsNothing);
    await tester.tap(find.byTooltip('Show the A2UI messages as they arrive'));
    await settle(tester);
    expect(find.byType(InspectorPanel), findsOneWidget);
    expect(wire.traces.length, traces);
    expect(
      find.text('Plan my first trip to Siargao, 4 days, mid budget'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('replay rebuilds the surface without a new request', (
    tester,
  ) async {
    final WireLog wire = await pumpInspected(tester, 'tab=home&inspect=1');
    final int traces = wire.traces.length;
    await tester.tap(find.byTooltip('Replay this surface message by message'));
    await tester.pump();
    expect(find.text('0/3 rendered'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.pump(WireLog.slowDelay);
    }
    await settle(tester);
    expect(find.text('3/3 rendered'), findsOneWidget);
    expect(wire.traces.length, traces);
  });

  group('WireLog', () {
    test('pace only applies while the panel is open', () {
      final WireLog wire = WireLog(pace: RenderPace.step);
      expect(wire.effectivePace, RenderPace.instant);
      wire.open = true;
      expect(wire.effectivePace, RenderPace.step);
    });

    test('step releases one waiter at a time, closing releases all', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final WireLog wire = WireLog(open: true, pace: RenderPace.step);
      var done = 0;
      unawaited(wire.waitForStep().then((_) => done++));
      unawaited(wire.waitForStep().then((_) => done++));
      unawaited(wire.waitForStep().then((_) => done++));
      wire.step();
      await Future<void>.delayed(Duration.zero);
      expect(done, 1);
      wire.open = false;
      await Future<void>.delayed(Duration.zero);
      expect(done, 3);
      expect(wire.canStep, isFalse);
    });

    test('summarizes A2UI messages', () {
      final List<Map<String, Object?>> m = threeMessages('s1');
      expect(summarizeA2ui(m[0]), contains('surface s1'));
      expect(summarizeA2ui(m[1]), '1 components: Stack');
      expect(summarizeA2ui(m[2]), startsWith('path /'));
    });
  });

  test('A2A logs the request, frames and one entry per A2UI message', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final WireLog wire = WireLog();
    final List<Map<String, Object?>> messages = threeMessages(
      'first_time_trip',
    );
    final MockClient client = MockClient(
      (request) async => http.Response(
        sse([
          {
            'kind': 'task',
            'id': 't1',
            'contextId': 'c1',
            'status': {'state': 'submitted'},
          },
          {
            'kind': 'status-update',
            'taskId': 't1',
            'contextId': 'c1',
            'final': true,
            'status': {
              'state': 'completed',
              'message': agentMessage([
                for (final Map<String, Object?> m in messages)
                  {'kind': 'data', 'data': m},
              ]),
            },
          },
        ]),
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
    );
    final AgentReply reply = await A2aService(
      agentUrl: 'http://agent.test',
      client: client,
      wire: wire,
    ).sendPrompt(prompt: 'Plan my first trip', format: ResponseFormat.a2ui);

    expect(reply.messages, hasLength(3));
    expect(reply.entries.map((e) => e.json), reply.messages);
    final WireTrace trace = wire.traces.single;
    expect(trace.channel, WireChannel.a2a);
    expect(trace.entries.map((e) => e.title), [
      'POST message/stream',
      'SSE task',
      'createSurface',
      'updateComponents',
      'updateDataModel',
    ]);
    expect(trace.entries.first.direction, WireDirection.outgoing);
  });
}
