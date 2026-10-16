import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:siargao_genui/a2ui/a2ui_surface_view.dart';
import 'package:siargao_genui/catalog/catalog_schemas.g.dart';
import 'package:siargao_genui/services/a2a_service.dart';
import 'package:siargao_genui/services/models.dart';

const String agentUrl = 'http://localhost:10002';

List<Map<String, Object?>> threeMessages(String surfaceId) => [
  {
    'version': 'v0.9',
    'createSurface': {'surfaceId': surfaceId, 'catalogId': siargaoCatalogId},
  },
  {
    'version': 'v0.9',
    'updateComponents': {
      'surfaceId': surfaceId,
      'components': [
        {'id': 'root', 'component': 'Stack', 'children': <String>[]},
      ],
    },
  },
  {
    'version': 'v0.9',
    'updateDataModel': {'surfaceId': surfaceId, 'path': '/', 'value': {}},
  },
];

/// An SSE body with one JSON-RPC frame per event.
String sse(List<Map<String, Object?>> results, {String id = '1'}) => results
    .map(
      (r) =>
          'event: message\ndata: ${jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': r})}\n\n',
    )
    .join();

Map<String, Object?> agentMessage(
  List<Map<String, Object?>> parts, {
  Map<String, Object?>? metadata,
}) => {
  'kind': 'message',
  'role': 'agent',
  'messageId': 'm1',
  'parts': parts,
  'metadata': ?metadata,
};

const Map<String, Object?> siargaoMeta = {
  'siargao': {
    'intent': 'first_time_trip',
    'source': 'template',
    'modelCalls': 0,
    'latencyMs': 12,
    'valid': true,
  },
};

void main() {
  group('request', () {
    test('sends message/stream with text part and siargao metadata', () async {
      late http.BaseRequest captured;
      late Map<String, Object?> body;
      final MockClient client = MockClient((request) async {
        captured = request;
        body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        return http.Response(
          sse([
            {
              'kind': 'task',
              'id': 't1',
              'contextId': 'c1',
              'status': {'state': 'submitted'},
            },
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final A2aService a2a = A2aService(agentUrl: agentUrl, client: client);
      await a2a.sendPrompt(
        prompt: 'Plan my first trip to Siargao, 4 days, mid budget',
        intent: 'first_time_trip',
      );

      expect(captured.method, 'POST');
      expect(captured.url.toString(), agentUrl);
      expect(captured.headers['Accept'], 'text/event-stream');
      expect(
        captured.headers['X-A2A-Extensions'],
        'https://a2ui.org/a2a-extension/a2ui/v0.9',
      );
      expect(body['jsonrpc'], '2.0');
      expect(body['method'], 'message/stream');
      final Map<String, Object?> message =
          ((body['params']! as Map)['message']! as Map).cast();
      expect(message['role'], 'user');
      expect(message['kind'], 'message');
      expect(message['messageId'], isA<String>());
      expect(message['parts'], [
        {
          'kind': 'text',
          'text': 'Plan my first trip to Siargao, 4 days, mid budget',
        },
      ]);
      final Map<String, Object?> metadata = (message['metadata']! as Map)
          .cast();
      expect(metadata['siargao'], {
        'responseFormat': 'a2ui',
        'intent': 'first_time_trip',
      });
      expect(
        ((metadata['a2uiClientCapabilities']! as Map)['v0.9']!
            as Map)['supportedCatalogIds'],
        [siargaoCatalogId],
      );
    });

    test('text format omits the intent when typed freely', () {
      expect(
        A2aService.requestMetadata(format: ResponseFormat.text)['siargao'],
        {'responseFormat': 'text'},
      );
    });

    test('actions go back as a v0.9 action DataPart in the context', () async {
      final List<Map<String, Object?>> bodies = [];
      final MockClient client = MockClient((request) async {
        bodies.add((jsonDecode(request.body) as Map).cast());
        return http.Response(
          sse([
            {
              'kind': 'status-update',
              'taskId': 't9',
              'contextId': 'ctx-1',
              'final': true,
              'status': {
                'state': 'completed',
                'message': agentMessage([
                  {'kind': 'text', 'text': 'Booked Cloud 9 Surf Cabins.'},
                ]),
              },
            },
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final A2aService a2a = A2aService(agentUrl: agentUrl, client: client);
      await a2a.sendPrompt(prompt: 'stays');
      final AgentReply reply = await a2a.sendAction(
        const SurfaceAction(
          name: 'choose_stay',
          sourceComponentId: 'stay-2',
          surfaceId: 'stays_near_cloud9',
          context: {'stayId': 'cloud9-surf-cabins', 'nights': 3},
          timestamp: '2026-10-17T09:00:00.000',
        ),
      );
      expect(reply.text, 'Booked Cloud 9 Surf Cabins.');
      final Map<String, Object?> message =
          ((bodies.last['params']! as Map)['message']! as Map).cast();
      expect(message['contextId'], 'ctx-1');
      expect(message['referenceTaskIds'], ['t9']);
      expect(message['parts'], [
        {
          'kind': 'data',
          'data': {
            'version': 'v0.9',
            'action': {
              'name': 'choose_stay',
              'sourceComponentId': 'stay-2',
              'surfaceId': 'stays_near_cloud9',
              'context': {'stayId': 'cloud9-surf-cabins', 'nights': 3},
              'timestamp': '2026-10-17T09:00:00.000',
            },
          },
        },
      ]);
    });
  });

  group('response', () {
    test('reads DataParts and metadata.siargao from a status update', () {
      final AgentReply reply = A2aService.parseFrames([
        for (final Map<String, Object?> r in [
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
                for (final Map<String, Object?> m in threeMessages(
                  'first_time_trip',
                ))
                  {
                    'kind': 'data',
                    'data': m,
                    'metadata': {'mimeType': 'application/a2ui+json'},
                  },
              ], metadata: siargaoMeta),
            },
          },
        ])
          {'jsonrpc': '2.0', 'id': '1', 'result': r},
      ]);
      expect(reply.messages, hasLength(3));
      expect(reply.messages.first.containsKey('createSurface'), isTrue);
      expect(reply.messages.last.containsKey('updateDataModel'), isTrue);
      expect(reply.meta?.modelCalls, 0);
      expect(reply.meta?.source, 'template');
      expect(reply.meta?.latencyMs, 12);
      expect(reply.meta?.valid, isTrue);
      expect(reply.meta?.label, '0 model calls · template');
      expect(reply.taskId, 't1');
      expect(reply.contextId, 'c1');
    });

    test('reads a plain message result and drops duplicate DataParts', () {
      final Map<String, Object?> create = threeMessages('x').first;
      final AgentReply reply = A2aService.parseFrames([
        {
          'jsonrpc': '2.0',
          'id': '1',
          'result': agentMessage(
            [
              {'kind': 'data', 'data': create},
              {'kind': 'data', 'data': create},
              {'kind': 'text', 'text': '## Heading\n\n- one'},
            ],
            metadata: {
              'siargao': {'source': 'model', 'modelCalls': 1},
            },
          ),
        },
      ]);
      expect(reply.messages, hasLength(1));
      expect(reply.text, '## Heading\n\n- one');
      expect(reply.meta?.label, '1 model call · model');
    });

    test('reads A2UI from artifact updates', () {
      final AgentReply reply = A2aService.parseFrames([
        {
          'jsonrpc': '2.0',
          'id': '1',
          'result': {
            'kind': 'artifact-update',
            'taskId': 't',
            'contextId': 'c',
            'append': false,
            'lastChunk': true,
            'artifact': {
              'artifactId': 'a',
              'parts': [
                for (final Map<String, Object?> m in threeMessages('y'))
                  {'kind': 'data', 'data': m},
              ],
              'metadata': siargaoMeta,
            },
          },
        },
      ]);
      expect(reply.messages, hasLength(3));
      expect(reply.meta?.intent, 'first_time_trip');
    });

    test('a failed task becomes a friendly error', () {
      expect(
        () => A2aService.parseFrames([
          {
            'jsonrpc': '2.0',
            'id': '1',
            'result': {
              'kind': 'status-update',
              'taskId': 't',
              'contextId': 'c',
              'status': {'state': 'failed'},
            },
          },
        ]),
        throwsA(
          isA<A2aException>().having(
            (e) => e.message,
            'message',
            contains('could not finish'),
          ),
        ),
      );
    });

    test('a JSON-RPC error becomes a friendly error', () {
      expect(
        () => A2aService.parseFrames([
          {
            'jsonrpc': '2.0',
            'id': '1',
            'error': {'code': -32603, 'message': 'boom'},
          },
        ]),
        throwsA(isA<A2aException>()),
      );
    });

    test('HTTP and network failures become friendly errors', () async {
      final A2aService down = A2aService(
        agentUrl: agentUrl,
        client: MockClient((_) async => http.Response('nope', 503)),
      );
      await expectLater(
        down.sendPrompt(prompt: 'hi'),
        throwsA(
          isA<A2aException>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
      final A2aService offline = A2aService(
        agentUrl: agentUrl,
        client: MockClient((_) async => throw http.ClientException('refused')),
      );
      await expectLater(
        offline.sendPrompt(prompt: 'hi'),
        throwsA(
          isA<A2aException>().having(
            (e) => e.message,
            'message',
            contains('Could not reach the agent'),
          ),
        ),
      );
    });

    test('a plain JSON response body is accepted too', () async {
      final A2aService a2a = A2aService(
        agentUrl: agentUrl,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': '1',
              'result': agentMessage([
                {'kind': 'text', 'text': 'Hello'},
              ], metadata: siargaoMeta),
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final AgentReply reply = await a2a.sendPrompt(
        prompt: 'hi',
        format: ResponseFormat.text,
      );
      expect(reply.text, 'Hello');
      expect(reply.meta?.modelCalls, 0);
    });
  });
}
