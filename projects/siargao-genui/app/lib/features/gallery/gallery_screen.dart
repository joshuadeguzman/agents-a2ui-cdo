import 'package:flutter/material.dart';

import '../../a2ui/response_surface.dart';
import '../../app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/badges.dart';
import '../../widgets/screen_header.dart';
import 'gallery_samples.dart';

/// Every catalog widget rendered from a static sample surface, through the
/// real catalog and a real SurfaceController.
class GalleryScreen extends StatelessWidget {
  /// Creates a [GalleryScreen].
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final EdgeInsets pad = pagePadding(constraints.maxWidth);
        return ListView.builder(
          padding: pad.copyWith(top: Gaps.lg, bottom: Gaps.xxl),
          itemCount: gallerySamples.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Gaps.xl),
                  child: ScreenHeader(
                    title: 'Widget gallery',
                    subtitle:
                        'The ${gallerySamples.length} catalog widgets with '
                        'sample data, rendered through genui.',
                    badges: const [
                      Pill(
                        label: 'Static samples',
                        icon: Icons.widgets_outlined,
                      ),
                    ],
                  ),
                ),
              );
            }
            final GallerySample sample = gallerySamples[i - 1];
            return ContentWidth(
              child: Padding(
                padding: const EdgeInsets.only(bottom: Gaps.xxl),
                child: _SampleSection(sample: sample),
              ),
            );
          },
        );
      },
    );
  }
}

class _SampleSection extends StatelessWidget {
  const _SampleSection({required this.sample});

  final GallerySample sample;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(sample.component, style: t.titleLarge),
        const SizedBox(height: Gaps.xs),
        Text(
          sample.description,
          style: t.bodyMedium?.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: Gaps.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(Radii.card + 4),
            border: Border.all(color: AppColors.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Gaps.xl),
            child: ResponseSurface(
              messages: sample.messages,
              onAction: (a) => handleSurfaceAction(context, a),
            ),
          ),
        ),
      ],
    );
  }
}
