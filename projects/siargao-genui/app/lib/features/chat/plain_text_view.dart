import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../theme/app_theme.dart';

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
        child: MarkdownBody(data: markdown, styleSheet: sheet),
      ),
    );
  }
}
