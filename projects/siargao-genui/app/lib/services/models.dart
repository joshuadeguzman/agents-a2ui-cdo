import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../inspector/wire_log.dart';

/// How a surface reached the app (docs/CONTRACT.md `path`).
enum DeliveryPath {
  /// A2A `message/stream` from the agent.
  a2a('a2a', 'A2A'),

  /// MCP `resources/read`.
  mcpResource('mcp_resource', 'MCP resource'),

  /// MCP `tools/call`.
  mcpTool('mcp_tool', 'MCP tool');

  const DeliveryPath(this.wire, this.label);

  /// Value used in fixtures.
  final String wire;

  /// Short label for the UI.
  final String label;

  /// Parses a fixture `path` value.
  static DeliveryPath parse(Object? value) => DeliveryPath.values.firstWhere(
    (p) => p.wire == value,
    orElse: () => DeliveryPath.a2a,
  );
}

/// `responseFormat` in the request metadata.
enum ResponseFormat {
  /// A2UI DataParts.
  a2ui,

  /// A markdown TextPart only.
  text,
}

/// The `siargao` metadata object on responses:
/// `{"intent", "source", "modelCalls", "latencyMs", "valid"}`.
@immutable
class ResponseMeta {
  /// Creates a [ResponseMeta].
  const ResponseMeta({
    this.intent,
    this.source,
    this.modelCalls,
    this.latencyMs,
    this.valid,
  });

  /// Reads the metadata object. Unknown or wrong types become null.
  factory ResponseMeta.fromJson(Map<String, Object?> json) {
    final Object? calls = json['modelCalls'];
    final Object? latency = json['latencyMs'];
    final Object? valid = json['valid'];
    return ResponseMeta(
      intent: json['intent'] is String ? json['intent'] as String : null,
      source: json['source'] is String ? json['source'] as String : null,
      modelCalls: calls is num ? calls.toInt() : null,
      latencyMs: latency is num ? latency.toInt() : null,
      valid: valid is bool ? valid : null,
    );
  }

  /// Reads `container[key]` when it is a map, else null.
  static ResponseMeta? maybeFrom(Object? container, [String key = 'siargao']) {
    if (container is! Map) return null;
    final Object? m = container[key];
    if (m is! Map) return null;
    return ResponseMeta.fromJson(m.cast<String, Object?>());
  }

  /// Routed intent.
  final String? intent;

  /// `template` or `model`.
  final String? source;

  /// Model calls that produced the response.
  final int? modelCalls;

  /// Server side latency.
  final int? latencyMs;

  /// Whether the server validated the A2UI.
  final bool? valid;

  /// For example `0 model calls · template` or `1 model call · model`.
  String get label {
    final int? n = modelCalls;
    final String calls = n == null
        ? 'Model calls unknown'
        : '$n model ${n == 1 ? 'call' : 'calls'}';
    final String? s = source;
    return s == null ? calls : '$calls · $s';
  }
}

/// One A2UI surface (and or a markdown answer) with its metadata.
@immutable
class SurfaceResponse {
  /// Creates a [SurfaceResponse].
  const SurfaceResponse({
    required this.path,
    this.messages = const [],
    this.text,
    this.meta,
    this.note,
    this.trace,
    this.entries = const [],
  });

  /// Delivery path.
  final DeliveryPath path;

  /// Decoded A2UI messages in order.
  final List<Map<String, Object?>> messages;

  /// Markdown text, if any.
  final String? text;

  /// Server metadata, if any.
  final ResponseMeta? meta;

  /// Extra honest context for the UI, for example how offline data was made.
  final String? note;

  /// The inspector trace for this response, if the log is on.
  final WireTrace? trace;

  /// Inspector entries for [messages], same order and length, or empty.
  final List<WireEntry> entries;

  /// True when there is something to render.
  bool get hasSurface => messages.isNotEmpty;
}

/// Decodes a JSON array of A2UI messages (the MCP `text` field). Also accepts
/// a single message object or `{"messages": [...]}`.
List<Map<String, Object?>> decodeA2uiMessages(String text) {
  final Object? decoded = jsonDecode(text);
  final Object? list = decoded is Map && decoded['messages'] is List
      ? decoded['messages']
      : decoded;
  if (list is List) {
    return [
      for (final Object? m in list)
        if (m is Map) m.cast<String, Object?>(),
    ];
  }
  if (list is Map) return [list.cast<String, Object?>()];
  throw const FormatException('Expected a JSON array of A2UI messages');
}

/// True when [data] is an A2UI server to client message.
bool isA2uiMessage(Map<Object?, Object?> data) =>
    data.containsKey('createSurface') ||
    data.containsKey('updateComponents') ||
    data.containsKey('updateDataModel') ||
    data.containsKey('deleteSurface');
