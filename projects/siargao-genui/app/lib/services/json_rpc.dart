import 'dart:convert';
import 'dart:math';

/// Splits a Server-Sent Events body into the JSON payloads of its `data:`
/// lines (multi-line data joined with a newline). Comments and `event:` or
/// `id:` lines are ignored.
List<Map<String, Object?>> parseSseJson(String body) {
  final List<Map<String, Object?>> out = [];
  final List<String> data = [];
  void flush() {
    if (data.isEmpty) return;
    final String payload = data.join('\n').trim();
    data.clear();
    if (payload.isEmpty) return;
    final Object? decoded = jsonDecode(payload);
    if (decoded is Map) out.add(decoded.cast<String, Object?>());
  }

  for (final String raw in const LineSplitter().convert(body)) {
    final String line = raw.trimRight();
    if (line.isEmpty) {
      flush();
    } else if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
    }
  }
  flush();
  return out;
}

/// Decodes a JSON-RPC response body that is either plain JSON or SSE.
List<Map<String, Object?>> decodeRpcBody(String body, String? contentType) {
  final String type = (contentType ?? '').toLowerCase();
  final String trimmed = body.trimLeft();
  if (type.contains('text/event-stream') ||
      trimmed.startsWith('data:') ||
      trimmed.startsWith('event:') ||
      trimmed.startsWith(':')) {
    return parseSseJson(body);
  }
  if (trimmed.isEmpty) return const [];
  final Object? decoded = jsonDecode(trimmed);
  if (decoded is Map) return [decoded.cast<String, Object?>()];
  if (decoded is List) {
    return [
      for (final Object? e in decoded)
        if (e is Map) e.cast<String, Object?>(),
    ];
  }
  return const [];
}

final Random _random = Random.secure();

/// A random v4 style UUID for message and request ids.
String newId() {
  final List<int> b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final String h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
