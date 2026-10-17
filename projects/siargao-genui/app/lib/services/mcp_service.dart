import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../inspector/wire_log.dart';
import 'json_rpc.dart';
import 'models.dart';

/// The A2UI MIME type over MCP (docs/CONTRACT.md).
const String a2uiMimeType = 'application/a2ui+json';

/// A failure talking to the MCP server, with a message fit for the UI.
class McpException implements Exception {
  /// Creates an [McpException].
  const McpException(this.message);

  /// Friendly description.
  final String message;

  @override
  String toString() => 'McpException: $message';
}

/// Plain JSON-RPC over HTTP POST to an MCP Streamable HTTP endpoint.
///
/// The server is stateless, so requests go straight out. If it answers that a
/// session is required, the client runs `initialize` once, keeps the
/// `Mcp-Session-Id` header, and retries.
class McpService {
  /// Creates an [McpService] for [mcpUrl].
  McpService({
    required this.mcpUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
    this.wire,
  }) : _client = client ?? http.Client();

  /// Records requests and results for the inspector, if set.
  final WireLog? wire;

  /// MCP endpoint, for example `http://localhost:10003/mcp`.
  final String mcpUrl;

  /// Request timeout.
  final Duration timeout;

  final http.Client _client;
  String? _sessionId;
  bool _initialized = false;

  /// `resources/read` for an A2UI resource such as `a2ui://home/first-run`.
  Future<SurfaceResponse> readResource(String uri) async {
    final WireTrace? trace = wire?.begin(WireChannel.mcpResource, uri);
    final Map<String, Object?> result = await _call('resources/read', {
      'uri': uri,
    }, trace: trace);
    final List<Object?> contents =
        (result['contents'] as List<Object?>?) ?? const [];
    for (final Object? c in contents) {
      if (c is Map && c['mimeType'] == a2uiMimeType && c['text'] is String) {
        final List<Map<String, Object?>> messages = _decode(
          c['text'] as String,
        );
        return SurfaceResponse(
          path: DeliveryPath.mcpResource,
          messages: messages,
          meta:
              ResponseMeta.maybeFrom(result['_meta']) ??
              ResponseMeta.maybeFrom(c['_meta']),
          trace: trace,
          entries: _logA2ui(trace, messages, 'resource contents[0].text'),
        );
      }
    }
    throw const McpException('The resource did not contain an A2UI surface.');
  }

  /// `tools/call` for a tool that returns an embedded A2UI resource, such as
  /// `search_stays`.
  Future<SurfaceResponse> callTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final WireTrace? trace = wire?.begin(
      WireChannel.mcpTool,
      '$name(${arguments.entries.map((e) => '${e.key}: ${e.value}').join(', ')})',
    );
    final Map<String, Object?> result = await _call('tools/call', {
      'name': name,
      'arguments': arguments,
    }, trace: trace);
    final List<Object?> content =
        (result['content'] as List<Object?>?) ?? const [];
    final List<String> texts = [];
    List<Map<String, Object?>>? messages;
    ResponseMeta? meta = ResponseMeta.maybeFrom(result['_meta']);
    for (final Object? item in content) {
      if (item is! Map) continue;
      if (item['type'] == 'text' && item['text'] is String) {
        texts.add(item['text'] as String);
      } else if (item['type'] == 'resource' && item['resource'] is Map) {
        final Map<Object?, Object?> res = item['resource'] as Map;
        if (res['mimeType'] == a2uiMimeType && res['text'] is String) {
          messages = _decode(res['text'] as String);
          meta ??= ResponseMeta.maybeFrom(res['_meta']);
        }
      }
    }
    if (result['isError'] == true) {
      throw McpException(
        texts.isEmpty ? 'The tool $name failed.' : texts.join(' '),
      );
    }
    if (messages == null) {
      throw McpException('The tool $name did not return an A2UI surface.');
    }
    return SurfaceResponse(
      path: DeliveryPath.mcpTool,
      messages: messages,
      text: texts.isEmpty ? null : texts.join('\n\n'),
      meta: meta,
      trace: trace,
      entries: _logA2ui(trace, messages, 'embedded resource text'),
    );
  }

  List<WireEntry> _logA2ui(
    WireTrace? trace,
    List<Map<String, Object?>> messages,
    String via,
  ) {
    if (trace == null) return const [];
    return wire!.addA2ui(trace, messages, via: via);
  }

  List<Map<String, Object?>> _decode(String text) {
    try {
      return decodeA2uiMessages(text);
    } on FormatException {
      throw const McpException('The A2UI payload was not valid JSON.');
    }
  }

  Future<Map<String, Object?>> _call(
    String method,
    Map<String, Object?> params, {
    bool retried = false,
    WireTrace? trace,
  }) async {
    final String id = newId();
    final Map<String, Object?> body = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };
    if (trace != null) {
      wire!.add(
        trace,
        WireDirection.outgoing,
        WireKind.request,
        'POST $method',
        summary: 'JSON-RPC over Streamable HTTP',
        json: body,
      );
    }
    final http.Response response = await _post(body);
    if ((response.statusCode == 400 || response.statusCode == 404) &&
        !retried &&
        response.body.toLowerCase().contains('session')) {
      await _initialize();
      return _call(method, params, retried: true, trace: trace);
    }
    if (response.statusCode >= 400) {
      throw McpException(
        'The MCP server answered with HTTP ${response.statusCode}.',
      );
    }
    final List<Map<String, Object?>> frames;
    try {
      frames = decodeRpcBody(response.body, response.headers['content-type']);
    } on FormatException {
      throw const McpException('The MCP server sent unreadable JSON.');
    }
    final Map<String, Object?> frame = frames.lastWhere(
      (f) => f['id'] == id || f.containsKey('result') || f.containsKey('error'),
      orElse: () =>
          throw const McpException('The MCP server sent an empty response.'),
    );
    final Object? error = frame['error'];
    if (error is Map) {
      throw McpException(
        'The MCP server reported an error: ${error['message'] ?? 'unknown'}.',
      );
    }
    final Object? result = frame['result'];
    if (result is! Map) {
      throw const McpException('The MCP server sent no result.');
    }
    if (trace != null) {
      wire!.add(
        trace,
        WireDirection.incoming,
        WireKind.frame,
        'result',
        summary: 'HTTP ${response.statusCode} · mimeType $a2uiMimeType',
        json: {...frame, 'result': elideA2uiText(result)},
      );
    }
    return result.cast<String, Object?>();
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    final http.Response init = await _post({
      'jsonrpc': '2.0',
      'id': newId(),
      'method': 'initialize',
      'params': {
        'protocolVersion': '2025-06-18',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'siargao_genui', 'version': '1.0.0'},
      },
    });
    if (init.statusCode >= 400) {
      throw McpException(
        'The MCP server refused to start a session (HTTP ${init.statusCode}).',
      );
    }
    _sessionId = init.headers['mcp-session-id'] ?? _sessionId;
    await _post({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    _initialized = true;
  }

  Future<http.Response> _post(Map<String, Object?> body) async {
    try {
      return await _client
          .post(
            Uri.parse(mcpUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/event-stream',
              'Mcp-Session-Id': ?_sessionId,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const McpException('The MCP server took too long to answer.');
    } on http.ClientException catch (e) {
      throw McpException(
        'Could not reach the MCP server at $mcpUrl (${e.message}).',
      );
    }
  }
}

/// A copy of an MCP result with each A2UI `text` payload replaced by a short
/// note. The inspector lists those messages one by one right after it.
Object? elideA2uiText(Object? node) {
  if (node is List) return [for (final Object? e in node) elideA2uiText(e)];
  if (node is! Map) return node;
  final bool a2ui = node['mimeType'] == a2uiMimeType && node['text'] is String;
  return {
    for (final MapEntry<Object?, Object?> e in node.entries)
      '${e.key}': a2ui && e.key == 'text'
          ? '<JSON array of A2UI messages, listed below>'
          : elideA2uiText(e.value),
  };
}
