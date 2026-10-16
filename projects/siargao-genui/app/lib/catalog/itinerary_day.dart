import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../theme/app_theme.dart';
import 'binding.dart';
import 'catalog_schemas.g.dart';
import 'image_asset.dart';

/// One timeline entry of an [ItineraryDayCard].
@immutable
class TimelineEntry {
  /// Creates a [TimelineEntry].
  const TimelineEntry({required this.time, required this.activity, this.note});

  /// Reads an entry from a JSON map.
  factory TimelineEntry.fromMap(Map<String, Object?> m) => TimelineEntry(
    time: m['time']?.toString() ?? '',
    activity: m['activity']?.toString() ?? '',
    note: (m['note']?.toString().trim().isEmpty ?? true)
        ? null
        : m['note'].toString(),
  );

  /// When, as shown to the user.
  final String time;

  /// What to do.
  final String activity;

  /// Optional detail.
  final String? note;
}

/// `ItineraryDay`: one day of a plan with a timeline.
final CatalogItem itineraryDayItem = CatalogItem(
  name: 'ItineraryDay',
  dataSchema: Schema.fromMap(itineraryDaySchema),
  widgetBuilder: (itemContext) {
    final Map<String, Object?> props = propsOf(itemContext);
    return BoundProps(
      dataContext: itemContext.dataContext,
      props: {
        'day': props['day'],
        'title': props['title'],
        'items': props['items'],
        'image': props['image'],
      },
      builder: (context, v) => ItineraryDayCard(
        day: v.number('day')?.toInt(),
        title: v.string('title') ?? '',
        imageKey: v.string('image'),
        items: v.maps('items').map(TimelineEntry.fromMap).toList(),
      ),
    );
  },
);

/// The Flutter widget behind `ItineraryDay`.
class ItineraryDayCard extends StatelessWidget {
  /// Creates an [ItineraryDayCard].
  const ItineraryDayCard({
    super.key,
    required this.day,
    required this.title,
    required this.items,
    this.imageKey,
  });

  /// Day number, starting at 1.
  final int? day;

  /// Theme of the day.
  final String title;

  /// Timeline entries.
  final List<TimelineEntry> items;

  /// Optional banner image key.
  final String? imageKey;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageKey != null)
            SiargaoImage(
              imageKey: imageKey,
              aspectRatio: 3 / 1,
              borderRadius: BorderRadius.zero,
              showAlt: false,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (day != null) ...[
                  _DayBadge(day: day!),
                  const SizedBox(height: Gaps.md),
                ],
                Text(noWidow(title), style: t.titleLarge),
                const SizedBox(height: Gaps.lg),
                for (var i = 0; i < items.length; i++)
                  _TimelineRow(entry: items[i], last: i == items.length - 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayBadge extends StatelessWidget {
  const _DayBadge({required this.day});

  final int day;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          'Day $day',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: AppColors.tealInk),
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.last});

  final TimelineEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 60,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                entry.time,
                style: t.labelLarge?.copyWith(
                  color: AppColors.teal,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 7),
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: AppColors.teal,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: AppColors.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Gaps.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : Gaps.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.activity,
                    style: t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  if (entry.note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.note!,
                      style: t.bodySmall?.copyWith(color: AppColors.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
