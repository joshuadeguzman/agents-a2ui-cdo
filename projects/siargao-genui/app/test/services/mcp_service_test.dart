import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:siargao_genui/catalog/catalog_schemas.g.dart';
import 'package:siargao_genui/services/mcp_service.dart';
import 'package:siargao_genui/services/models.dart';

const String mcpUrl = 'http://localhost:10003/mcp';

final List<Map<String, Object?>> messages = [
  {
    'version': 'v0.9',
    'createSurface': {
      'surfaceId': 'home_first_run',
      'catalogId': siargaoCatalogId,
    },
  },
  {
    'version': 'v0.9',
    'updateComponents': {
      'surfaceId': 'home_first_run',
      'components': [
        {'id': 'root', 'component': 'Stack', 'children': <String>[]},
      ],
    },
  },
  {
    'version': 'v0.9',
    'updateDataModel': {
      'surfaceId': 'home_first_run',
      'path': '/',
      'value': {},
    },
  },
];

const Map<String, Object?> meta = {
  'siargao': {
    'intent': 'home_first_run',
    'source': 'template',
    'modelCalls': 0,
    'latencyMs': 3,
    'valid': true,
  },
};

http.Response rpc(Object? id, Map<String, Object?> result, {bool sse = false}) {
  final String json = jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  });
  return sse
      ? http.Response(
          'event: message\ndata: $json\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        )
      : http.Response(json, 200, headers: {'content-type': 'application/json'});
}

void main() {
  test('resources/read returns the A2UI messages and _meta.siargao', () async {
    late Map<String, Object?> body;
    late http.Request request;
    final McpService mcp = McpService(
      mcpUrl: mcpUrl,
      client: MockClient((r) async {
        request = r;
        body = (jsonDecode(r.body) as Map).cast();
        return rpc(body['id'], {
          'contents': [
            {
              'uri': 'a2ui://home/first-run',
              'mimeType': 'application/a2ui+json',
              'text': jsonEncode(messages),
            },
          ],
          '_meta': meta,
        });
      }),
    );
    final SurfaceResponse r = await mcp.readResource('a2ui://home/first-run');

    expect(request.method, 'POST');
    expect(request.url.toString(), mcpUrl);
    expect(request.headers['Accept'], 'application/json, text/event-stream');
    expect(body['jsonrpc'], '2.0');
    expect(body['method'], 'resources/read');
    expect(body['params'], {'uri': 'a2ui://home/first-run'});
    expect(r.path, DeliveryPath.mcpResource);
    expect(r.messages, messages);
    expect(r.meta?.label, '0 model calls · template');
  });

  test(
    'tools/call search_stays reads the embedded resource and text',
    () async {
      late Map<String, Object?> body;
      final McpService mcp = McpService(
        mcpUrl: mcpUrl,
        client: MockClient((r) async {
          body = (jsonDecode(r.body) as Map).cast();
          return rpc(body['id'], {
            'content': [
              {
                'type': 'resource',
                'resource': {
                  'uri': 'a2ui://search/stays',
                  'mimeType': 'application/a2ui+json',
                  'text': jsonEncode(messages),
                },
              },
              {'type': 'text', 'text': '4 stays near Cloud 9 under PHP 4,500.'},
            ],
            '_meta': meta,
            'isError': false,
          }, sse: true);
        }),
      );
      final SurfaceResponse r = await mcp.callTool('search_stays', {
        'area': 'Cloud 9',
        'nights': 3,
        'max_price': 4500,
      });
      expect(body['method'], 'tools/call');
      expect(body['params'], {
        'name': 'search_stays',
        'arguments': {'area': 'Cloud 9', 'nights': 3, 'max_price': 4500},
      });
      expect(r.path, DeliveryPath.mcpTool);
      expect(r.messages, hasLength(3));
      expect(r.text, '4 stays near Cloud 9 under PHP 4,500.');
      expect(r.meta?.modelCalls, 0);
    },
  );

  test('a tool error becomes a friendly McpException', () async {
    final McpService mcp = McpService(
      mcpUrl: mcpUrl,
      client: MockClient(
        (r) async => rpc((jsonDecode(r.body) as Map)['id'], {
          'content': [
            {'type': 'text', 'text': 'max_price must be positive'},
          ],
          'isError': true,
        }),
      ),
    );
    await expectLater(
      mcp.callTool('search_stays', {}),
      throwsA(
        isA<McpException>().having(
          (e) => e.message,
          'message',
          'max_price must be positive',
        ),
      ),
    );
  });

  test('a JSON-RPC error and HTTP errors are friendly', () async {
    final McpService rpcError = McpService(
      mcpUrl: mcpUrl,
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': (jsonDecode(r.body) as Map)['id'],
            'error': {'code': -32602, 'message': 'Unknown resource'},
          }),
          200,
        ),
      ),
    );
    await expectLater(
      rpcError.readResource('a2ui://nope'),
      throwsA(isA<McpException>()),
    );
    final McpService down = McpService(
      mcpUrl: mcpUrl,
      client: MockClient((_) async => http.Response('', 502)),
    );
    await expectLater(
      down.readResource('a2ui://home/first-run'),
      throwsA(
        isA<McpException>().having(
          (e) => e.message,
          'message',
          contains('502'),
        ),
      ),
    );
  });

  test('initializes a session when the server asks for one', () async {
    final List<String> methods = [];
    final List<String?> sessionHeaders = [];
    final McpService mcp = McpService(
      mcpUrl: mcpUrl,
      client: MockClient((r) async {
        final Map<String, Object?> body = (jsonDecode(r.body) as Map).cast();
        final String method = body['method']! as String;
        methods.add(method);
        sessionHeaders.add(r.headers['Mcp-Session-Id']);
        if (method == 'initialize') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {'protocolVersion': '2025-06-18'},
            }),
            200,
            headers: {'mcp-session-id': 'abc'},
          );
        }
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        if (r.headers['Mcp-Session-Id'] == null) {
          return http.Response('Bad Request: Missing session ID', 400);
        }
        return rpc(body['id'], {
          'contents': [
            {
              'uri': 'a2ui://home/first-run',
              'mimeType': 'application/a2ui+json',
              'text': jsonEncode(messages),
            },
          ],
        });
      }),
    );
    final SurfaceResponse r = await mcp.readResource('a2ui://home/first-run');
    expect(r.messages, hasLength(3));
    expect(methods, [
      'resources/read',
      'initialize',
      'notifications/initialized',
      'resources/read',
    ]);
    expect(sessionHeaders.last, 'abc');
  });

  test('a resource without A2UI content is a friendly error', () async {
    final McpService mcp = McpService(
      mcpUrl: mcpUrl,
      client: MockClient(
        (r) async => rpc((jsonDecode(r.body) as Map)['id'], {
          'contents': [
            {'uri': 'x', 'mimeType': 'text/plain', 'text': 'hi'},
          ],
        }),
      ),
    );
    await expectLater(mcp.readResource('x'), throwsA(isA<McpException>()));
  });
}
