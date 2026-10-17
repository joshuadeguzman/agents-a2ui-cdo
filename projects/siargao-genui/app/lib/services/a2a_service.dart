import 'dart:async';
import 'dart:convert';

import 'package:genui_a2a/genui_a2a.dart' show a2uiExtensionUri;
import 'package:http/http.dart' as http;

import '../a2ui/a2ui_surface_view.dart';
import '../catalog/catalog_schemas.g.dart';
import '../inspector/wire_log.dart';
import 'json_rpc.dart';
import 'models.dart';

/// A failure talking to the agent, with a message fit for the UI.
class A2aException implements Exception {
  /// Creates an [A2aException].
  const A2aException(this.message);

  /// Friendly description.
  final String message;

  @override
  String toString() => 'A2aException: $message';
}

/// Everything the agent sent back for one request.
class AgentReply {
  /// Creates an [AgentReply].
  const AgentReply({
    required this.messages,
    this.text,
    this.meta,
    this.taskId,
    this.contextId,
    this.trace,
    this.entries = const [],
  });

  /// A2UI messages from DataParts, in order, without duplicates.
  final List<Map<String, Object?>> messages;

  /// Inspector trace, when a [WireLog] is attached.
  final WireTrace? trace;

  /// Inspector entries for [messages], same order.
  final List<WireEntry> entries;

  /// Markdown text from the last message that had text.
  final String? text;

  /// The `metadata.siargao` object from the response message.
  final ResponseMeta? meta;

  /// A2A task id.
  final String? taskId;

  /// A2A context id.
  final String? contextId;
}

/// Minimal A2A 0.3 JSON-RPC client for `message/stream` over SSE.
///
/// genui_a2a 0.10.1 exports only `A2uiAgentConnector`, `A2AClient` and
/// `AgentCard`. The connector replaces the request message `metadata` with its
/// own and drops the response message `metadata`, and `A2AClient` needs the
/// unexported `Message` model and throws on `kind: "message"` results. The
/// demo needs to send `metadata.siargao` and read it back, so this client
/// speaks the same wire format directly (same method, headers and A2UI
/// extension URI as genui_a2a).
class A2aService {
  /// Creates an [A2aService] for the agent at [agentUrl].
  A2aService({
    required this.agentUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 90),
    this.wire,
  }) : _client = client ?? http.Client();

  /// Records requests and frames for the inspector, if set.
  final WireLog? wire;

  /// A2A base URL (the JSON-RPC endpoint).
  final String agentUrl;

  /// Request timeout.
  final Duration timeout;

  final http.Client _client;

  /// Context of the last A2UI conversation, used for follow-up actions.
  String? lastContextId;

  /// Task of the last A2UI conversation.
  String? lastTaskId;

  /// The request metadata from docs/CONTRACT.md plus the A2UI client
  /// capabilities, so an a2ui-agent-sdk agent picks the Siargao catalog.
  static Map<String, Object?> requestMetadata({
    required ResponseFormat format,
    String? intent,
  }) => {
    'siargao': {
      'responseFormat': format.name,
      if (intent != null && intent.isNotEmpty) 'intent': intent,
    },
    'a2uiClientCapabilities': {
      'v0.9': {
        'supportedCatalogIds': [siargaoCatalogId],
      },
    },
  };

  /// Sends a prompt. Pass [intent] when the user tapped a demo chip.
  Future<AgentReply> sendPrompt({
    required String prompt,
    String? intent,
    ResponseFormat format = ResponseFormat.a2ui,
  }) async {
    final AgentReply reply = await _stream(
      wire?.begin(
        WireChannel.a2a,
        prompt,
        textOnly: format == ResponseFormat.text,
      ),
      {
        'kind': 'message',
        'role': 'user',
        'messageId': newId(),
        'parts': [
          {'kind': 'text', 'text': prompt},
        ],
        'metadata': requestMetadata(format: format, intent: intent),
        'extensions': [a2uiExtensionUri.toString()],
      },
    );
    if (format == ResponseFormat.a2ui) {
      lastContextId = reply.contextId ?? lastContextId;
      lastTaskId = reply.taskId ?? lastTaskId;
    }
    return reply;
  }

  /// Sends a user action as a DataPart
  /// `{"version": "v0.9", "action": {...}}` in the last A2UI context.
  Future<AgentReply> sendAction(SurfaceAction action) {
    return _stream(wire?.begin(WireChannel.a2a, 'Action: ${action.name}'), {
      'kind': 'message',
      'role': 'user',
      'messageId': newId(),
      'parts': [
        {
          'kind': 'data',
          'data': {'version': 'v0.9', 'action': action.toJson()},
        },
      ],
      'contextId': ?lastContextId,
      if (lastTaskId != null) 'referenceTaskIds': [lastTaskId],
      'extensions': [a2uiExtensionUri.toString()],
    });
  }

  Future<AgentReply> _stream(
    WireTrace? trace,
    Map<String, Object?> message,
  ) async {
    try {
      final AgentReply reply = await _streamOnce(trace, message);
      finishTrace(wire, trace, meta: reply.meta);
      return reply;
    } on A2aException catch (e) {
      finishTrace(wire, trace, error: e.message);
      rethrow;
    }
  }

  Future<AgentReply> _streamOnce(
    WireTrace? trace,
    Map<String, Object?> message,
  ) async {
    final String id = newId();
    final Map<String, Object?> body = {
      'jsonrpc': '2.0',
      'id': id,
      'method': 'message/stream',
      'params': {'message': message},
    };
    if (trace != null) {
      wire?.add(
        trace,
        WireDirection.outgoing,
        WireKind.request,
        'POST message/stream',
        summary: _describeRequest(message),
        json: body,
      );
    }
    final http.Request request = http.Request('POST', Uri.parse(agentUrl))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'X-A2A-Extensions': a2uiExtensionUri.toString(),
      })
      ..body = jsonEncode(body);

    final _Collector c = _Collector();
    final List<WireEntry> entries = [];
    void onFrame(Map<String, Object?> frame) {
      final int before = c.messages.length;
      final String? textBefore = c.text;
      try {
        _foldFrame(c, frame);
      } finally {
        if (trace != null) {
          _logFrame(trace, frame, c, before, textBefore, entries);
        }
      }
    }

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
      if (response.statusCode >= 400) {
        throw A2aException(
          'The agent answered with HTTP ${response.statusCode}.',
        );
      }
      final String type = (response.headers['content-type'] ?? '')
          .toLowerCase();
      final Stream<String> lines = response.stream
          .timeout(timeout)
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      if (type.contains('text/event-stream')) {
        // Fold each SSE event as it arrives, so the inspector shows real
        // arrival times.
        final List<String> data = [];
        void flush() {
          if (data.isEmpty) return;
          final String payload = data.join('\n').trim();
          data.clear();
          if (payload.isEmpty) return;
          final Object? decoded = jsonDecode(payload);
          if (decoded is Map) onFrame(decoded.cast<String, Object?>());
        }

        await for (final String raw in lines) {
          final String line = raw.trimRight();
          if (line.isEmpty) {
            flush();
          } else if (line.startsWith('data:')) {
            data.add(line.substring(5).trimLeft());
          }
        }
        flush();
      } else {
        final String text = (await lines.toList()).join('\n');
        decodeRpcBody(text, type).forEach(onFrame);
      }
    } on TimeoutException {
      throw const A2aException('The agent took too long to answer.');
    } on http.ClientException catch (e) {
      throw A2aException(
        'Could not reach the agent at $agentUrl (${e.message}).',
      );
    } on FormatException {
      throw const A2aException(
        'The agent sent a response the app could not read.',
      );
    }
    final AgentReply reply = c.build();
    return AgentReply(
      messages: reply.messages,
      text: reply.text,
      meta: reply.meta,
      taskId: reply.taskId,
      contextId: reply.contextId,
      trace: trace,
      entries: entries,
    );
  }

  void _logFrame(
    WireTrace trace,
    Map<String, Object?> frame,
    _Collector c,
    int before,
    String? textBefore,
    List<WireEntry> entries,
  ) {
    final WireLog log = wire!;
    final Object? result = frame['result'];
    final String kind = result is Map
        ? '${result['kind'] ?? 'result'}'
        : 'error';
    final List<Map<String, Object?>> added = c.messages.sublist(before);
    if (added.isNotEmpty) {
      entries.addAll(log.addA2ui(trace, added, via: 'SSE $kind DataPart'));
      return;
    }
    final Object? status = result is Map ? result['status'] : null;
    final String? state = status is Map ? status['state']?.toString() : null;
    final bool newText = c.text != null && c.text != textBefore;
    log.add(
      trace,
      WireDirection.incoming,
      newText ? WireKind.text : WireKind.frame,
      'SSE $kind',
      summary: [
        ?state,
        if (newText) 'text part',
        if (c.meta != null && state == 'completed') c.meta!.label,
      ].join(' · '),
      json: frame,
    );
  }

  static String _describeRequest(Map<String, Object?> message) {
    final List<Object?> parts = (message['parts'] as List<Object?>?) ?? [];
    final Object? first = parts.isEmpty ? null : parts.first;
    final Object? meta = message['metadata'];
    final Object? siargao = meta is Map ? meta['siargao'] : null;
    final String format = siargao is Map
        ? 'responseFormat ${siargao['responseFormat']}'
        : 'action';
    if (first is Map && first['kind'] == 'data') return 'DataPart · $format';
    return 'TextPart · $format';
  }

  /// Folds JSON-RPC frames (each `{"result": ...}` or `{"error": ...}`) into
  /// one [AgentReply]. Public for tests.
  static AgentReply parseFrames(List<Map<String, Object?>> frames) {
    final _Collector c = _Collector();
    for (final Map<String, Object?> f in frames) {
      _foldFrame(c, f);
    }
    return c.build();
  }

  static void _foldFrame(_Collector c, Map<String, Object?> frame) {
    final Object? error = frame['error'];
    if (error is Map) {
      throw A2aException(
        'The agent reported an error: ${error['message'] ?? 'unknown'}.',
      );
    }
    final Object? result = frame.containsKey('result')
        ? frame['result']
        : frame;
    if (result is Map) c.addResult(result.cast<String, Object?>());
  }
}

class _Collector {
  final List<Map<String, Object?>> messages = [];
  final Set<String> _seen = {};
  String? text;
  ResponseMeta? meta;
  String? taskId;
  String? contextId;

  void addResult(Map<String, Object?> r) {
    switch (r['kind']) {
      case 'task':
        taskId = r['id'] as String? ?? taskId;
        contextId = r['contextId'] as String? ?? contextId;
        meta = ResponseMeta.maybeFrom(r['metadata']) ?? meta;
        for (final Object? a in (r['artifacts'] as List<Object?>?) ?? []) {
          if (a is Map) _addArtifact(a.cast<String, Object?>());
        }
        _addStatus(r['status']);
      case 'status-update':
        taskId = r['taskId'] as String? ?? taskId;
        contextId = r['contextId'] as String? ?? contextId;
        meta = ResponseMeta.maybeFrom(r['metadata']) ?? meta;
        _addStatus(r['status']);
      case 'artifact-update':
        taskId = r['taskId'] as String? ?? taskId;
        contextId = r['contextId'] as String? ?? contextId;
        final Object? a = r['artifact'];
        if (a is Map) _addArtifact(a.cast<String, Object?>());
      case 'message':
        taskId = r['taskId'] as String? ?? taskId;
        contextId = r['contextId'] as String? ?? contextId;
        _addMessage(r);
    }
  }

  void _addStatus(Object? status) {
    if (status is! Map) return;
    final Object? state = status['state'];
    final Object? message = status['message'];
    if (state == 'failed' || state == 'rejected' || state == 'canceled') {
      final String? why = message is Map ? _textOf(message['parts']) : null;
      throw A2aException(
        why == null || why.isEmpty
            ? 'The agent could not finish this request ($state).'
            : why,
      );
    }
    if (message is Map) _addMessage(message.cast<String, Object?>());
  }

  void _addArtifact(Map<String, Object?> artifact) {
    meta = ResponseMeta.maybeFrom(artifact['metadata']) ?? meta;
    _addParts(artifact['parts']);
  }

  void _addMessage(Map<String, Object?> message) {
    if (message['role'] == 'user') return;
    meta = ResponseMeta.maybeFrom(message['metadata']) ?? meta;
    _addParts(message['parts']);
  }

  void _addParts(Object? parts) {
    if (parts is! List) return;
    final StringBuffer buffer = StringBuffer();
    for (final Object? part in parts) {
      if (part is! Map) continue;
      final Object? kind = part['kind'];
      final Object? data = part['data'];
      if ((kind == 'data' || kind == null) && data is Map) {
        if (isA2uiMessage(data)) {
          final String key = jsonEncode(data);
          if (_seen.add(key)) messages.add(data.cast<String, Object?>());
        }
      } else if (kind == 'text' || part['text'] is String) {
        final Object? t = part['text'];
        if (t is String && t.trim().isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n\n');
          buffer.write(t.trim());
        }
      }
    }
    if (buffer.isNotEmpty) text = buffer.toString();
  }

  static String? _textOf(Object? parts) {
    if (parts is! List) return null;
    return parts
        .whereType<Map<Object?, Object?>>()
        .map((p) => p['text'])
        .whereType<String>()
        .join(' ')
        .trim();
  }

  AgentReply build() => AgentReply(
    messages: messages,
    text: text,
    meta: meta,
    taskId: taskId,
    contextId: contextId,
  );
}
