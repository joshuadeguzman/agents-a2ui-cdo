import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../theme/app_theme.dart';

/// Glues the last two words of markdown headings and bold-only lines so a
/// wrapped heading never leaves one word alone on its last line.
String gluePhraseEnds(String markdown) {
  final RegExp heading = RegExp(r'^(#{1,6} |\*\*).*');
  return markdown
      .split('\n')
      .map((line) {
        final String t = line.trimRight();
        if (!heading.hasMatch(t)) return line;
        final int i = t.lastIndexOf(' ');
        if (i <= 0 || t.length - i > 16) return line;
        return '${t.substring(0, i)}\u00A0${t.substring(i + 1)}';
      })
      .join('\n');
}

/// Renders the agent's markdown answer in a readable card.
class PlainTextView extends StatelessWidget {
  /// Creates a [PlainTextView].
  const PlainTextView({super.key, required this.markdown});

  /// Markdown source.
  final String markdown;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme t = theme.textTheme;
    final MarkdownStyleSheet sheet = MarkdownStyleSheet.fromTheme(theme)
        .copyWith(
          p: t.bodyLarge,
          pPadding: const EdgeInsets.only(bottom: 4),
          h1: t.headlineMedium,
          h2: t.headlineSmall,
          h3: t.titleLarge,
          h2Padding: const EdgeInsets.only(bottom: 4),
          strong: const TextStyle(fontWeight: FontWeight.w700),
          listBullet: t.bodyLarge?.copyWith(color: AppColors.teal),
          listIndent: 22,
          blockSpacing: 14,
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
        child: MarkdownBody(data: gluePhraseEnds(markdown), styleSheet: sheet),
      ),
    );
  }
}
