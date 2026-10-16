import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../theme/app_theme.dart';
import 'binding.dart';
import 'catalog_schemas.g.dart';

/// Visual tone of a [LocalNoteView].
enum NoteTone {
  /// Helpful advice.
  tip,

  /// Safety, weather, cash or timing warning.
  headsUp,

  /// Insider recommendation.
  local;

  /// Parses the catalog value (`tip`, `heads_up`, `local`).
  static NoteTone parse(Object? value) => switch (value) {
    'heads_up' => NoteTone.headsUp,
    'local' => NoteTone.local,
    _ => NoteTone.tip,
  };
}

/// `LocalNote`: callout for a tip, a heads up, or a local insider note.
final CatalogItem localNoteItem = CatalogItem(
  name: 'LocalNote',
  dataSchema: Schema.fromMap(localNoteSchema),
  widgetBuilder: (itemContext) {
    final Map<String, Object?> props = propsOf(itemContext);
    return BoundProps(
      dataContext: itemContext.dataContext,
      props: {
        'title': props['title'],
        'body': props['body'],
        'author': props['author'],
      },
      builder: (context, v) => LocalNoteView(
        title: v.string('title') ?? '',
        body: v.string('body') ?? '',
        author: v.string('author'),
        tone: NoteTone.parse(props['tone']),
      ),
    );
  },
);

/// The Flutter widget behind `LocalNote`.
class LocalNoteView extends StatelessWidget {
  /// Creates a [LocalNoteView].
  const LocalNoteView({
    super.key,
    required this.title,
    required this.body,
    this.tone = NoteTone.tip,
    this.author,
  });

  /// Headline.
  final String title;

  /// Advice text.
  final String body;

  /// Visual tone.
  final NoteTone tone;

  /// Optional attribution.
  final String? author;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final (Color bg, Color ink, IconData icon, String kind) = switch (tone) {
      NoteTone.tip => (
        AppColors.tealSoft,
        AppColors.tealInk,
        Icons.lightbulb_outline_rounded,
        'Tip',
      ),
      NoteTone.headsUp => (
        AppColors.amberSoft,
        AppColors.amberInk,
        Icons.warning_amber_rounded,
        'Heads up',
      ),
      NoteTone.local => (
        AppColors.coralSoft,
        AppColors.coralInk,
        Icons.favorite_outline_rounded,
        'Local insight',
      ),
    };
    return Semantics(
      container: true,
      label: kind,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 24, 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: ink, size: 24),
              ),
              const SizedBox(width: Gaps.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.toUpperCase(),
                      style: t.labelSmall?.copyWith(color: ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      noWidow(title),
                      style: t.titleMedium?.copyWith(color: AppColors.ink),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      style: t.bodyLarge?.copyWith(color: AppColors.ink),
                    ),
                    if (author != null) ...[
                      const SizedBox(height: Gaps.sm),
                      Text(
                        author!,
                        style: t.bodySmall?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
