import 'dart:convert';

import 'package:flutter/material.dart';

/// Colors for the dark inspector.
abstract final class WireColors {
  /// Panel background.
  static const Color background = Color(0xFF0E1A1C);

  /// Cards on the panel.
  static const Color card = Color(0xFF16282B);

  /// Card while its message is the next to render.
  static const Color cardActive = Color(0xFF1D3D41);

  /// Hairlines.
  static const Color line = Color(0xFF2A4245);

  /// Main text.
  static const Color text = Color(0xFFE8F0F1);

  /// Secondary text.
  static const Color muted = Color(0xFFA3B8BB);

  /// Accent, a light teal that reads on the dark background.
  static const Color accent = Color(0xFF6AD8E0);

  /// Outgoing arrows.
  static const Color outgoing = Color(0xFFF2C46B);

  /// Rendered checkmarks.
  static const Color rendered = Color(0xFF8BDB9A);

  /// JSON keys.
  static const Color key = Color(0xFF8AD4DC);

  /// JSON strings.
  static const Color string = Color(0xFFC9E79A);

  /// JSON numbers.
  static const Color number = Color(0xFFF7A072);

  /// JSON true, false and null.
  static const Color literal = Color(0xFFCDA6F0);
}

/// Monospace family bundled with the app (Roboto Mono).
const String monoFontFamily = 'RobotoMono';

/// Pretty printed, syntax colored JSON that can be selected and copied.
class JsonView extends StatelessWidget {
  /// Creates a [JsonView].
  const JsonView({super.key, required this.value, this.fontSize = 13});

  /// Any JSON value.
  final Object? value;

  /// Text size.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final List<TextSpan> spans = [];
    _write(spans, value, 0);
    return SelectableText.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: monoFontFamily,
          fontSize: fontSize,
          height: 1.45,
          color: WireColors.muted,
        ),
        children: spans,
      ),
    );
  }

  static const String _indent = '  ';

  static void _write(List<TextSpan> out, Object? v, int depth) {
    final String pad = _indent * depth;
    final String inner = _indent * (depth + 1);
    if (v is Map) {
      if (v.isEmpty) {
        out.add(const TextSpan(text: '{}'));
        return;
      }
      out.add(const TextSpan(text: '{\n'));
      final List<MapEntry<Object?, Object?>> entries = v.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        out
          ..add(TextSpan(text: inner))
          ..add(
            TextSpan(
              text: jsonEncode('${entries[i].key}'),
              style: const TextStyle(color: WireColors.key),
            ),
          )
          ..add(const TextSpan(text: ': '));
        _write(out, entries[i].value, depth + 1);
        out.add(TextSpan(text: i == entries.length - 1 ? '\n' : ',\n'));
      }
      out.add(TextSpan(text: '$pad}'));
    } else if (v is List) {
      if (v.isEmpty) {
        out.add(const TextSpan(text: '[]'));
        return;
      }
      out.add(const TextSpan(text: '[\n'));
      for (var i = 0; i < v.length; i++) {
        out.add(TextSpan(text: inner));
        _write(out, v[i], depth + 1);
        out.add(TextSpan(text: i == v.length - 1 ? '\n' : ',\n'));
      }
      out.add(TextSpan(text: '$pad]'));
    } else if (v is String) {
      out.add(
        TextSpan(
          text: jsonEncode(v),
          style: const TextStyle(color: WireColors.string),
        ),
      );
    } else if (v is num) {
      out.add(
        TextSpan(
          text: '$v',
          style: const TextStyle(color: WireColors.number),
        ),
      );
    } else {
      out.add(
        TextSpan(
          text: '$v',
          style: const TextStyle(color: WireColors.literal),
        ),
      );
    }
  }
}
