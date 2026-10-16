import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../theme/app_theme.dart';
import 'binding.dart';
import 'catalog_schemas.g.dart';
import 'image_asset.dart';

/// `StayCard`: one bookable option with a price and a Choose button.
final CatalogItem stayCardItem = CatalogItem(
  name: 'StayCard',
  dataSchema: Schema.fromMap(stayCardSchema),
  widgetBuilder: (itemContext) {
    final Map<String, Object?> props = propsOf(itemContext);
    return BoundProps(
      dataContext: itemContext.dataContext,
      props: {
        'image': props['image'],
        'name': props['name'],
        'note': props['note'],
        'pricePerNight': props['pricePerNight'],
        'priceUnit': props['priceUnit'],
        'currency': props['currency'],
        'area': props['area'],
        'rating': props['rating'],
        'actionLabel': props['actionLabel'],
      },
      builder: (context, v) => StayCardView(
        imageKey: v.string('image'),
        name: v.string('name') ?? '',
        note: v.string('note'),
        price: v.number('pricePerNight'),
        priceUnit: v.string('priceUnit') ?? 'per night',
        currency: v.string('currency') ?? 'PHP',
        area: v.string('area'),
        rating: v.number('rating'),
        actionLabel: v.string('actionLabel') ?? 'Choose',
        onPressed: () => dispatchAction(itemContext, props['action']),
      ),
    );
  },
);

/// The Flutter widget behind `StayCard`.
class StayCardView extends StatelessWidget {
  /// Creates a [StayCardView].
  const StayCardView({
    super.key,
    required this.name,
    this.imageKey,
    this.note,
    this.price,
    this.priceUnit = 'per night',
    this.currency = 'PHP',
    this.area,
    this.rating,
    this.actionLabel = 'Choose',
    this.onPressed,
  });

  /// Image key.
  final String? imageKey;

  /// Name of the option.
  final String name;

  /// One line on why it fits.
  final String? note;

  /// Price in [currency].
  final num? price;

  /// Text after the price.
  final String priceUnit;

  /// ISO currency code.
  final String currency;

  /// Where it is.
  final String? area;

  /// Guest rating from 0 to 5.
  final num? rating;

  /// Button label.
  final String actionLabel;

  /// Button callback.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SiargaoImage(
            imageKey: imageKey,
            aspectRatio: 3 / 2,
            borderRadius: BorderRadius.zero,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(noWidow(name), style: t.titleLarge),
                if (area != null || rating != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (area != null) ...[
                        const Icon(
                          Icons.place_outlined,
                          size: 18,
                          color: AppColors.inkMuted,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            area!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyMedium?.copyWith(
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ),
                      ],
                      if (rating != null) ...[
                        const SizedBox(width: Gaps.md),
                        const Icon(
                          Icons.star_rounded,
                          size: 19,
                          color: Color(0xFFB7791F),
                        ),
                        const SizedBox(width: 2),
                        Text(rating!.toStringAsFixed(1), style: t.labelLarge),
                      ],
                    ],
                  ),
                ],
                if (note != null) ...[
                  const SizedBox(height: Gaps.sm),
                  Text(note!, style: t.bodyMedium),
                ],
                const SizedBox(height: Gaps.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (price != null)
                            Text(
                              formatMoney(price!, currency: currency),
                              style: t.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.teal,
                              ),
                            ),
                          Text(
                            priceUnit,
                            style: t.bodySmall?.copyWith(
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gaps.md),
                    FilledButton(
                      onPressed: onPressed,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      child: Text(actionLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
