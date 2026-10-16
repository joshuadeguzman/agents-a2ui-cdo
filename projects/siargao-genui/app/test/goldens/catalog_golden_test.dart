import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siargao_genui/a2ui/a2ui_surface_view.dart';
import 'package:siargao_genui/a2ui/surface_session.dart';
import 'package:siargao_genui/features/gallery/gallery_samples.dart';
import 'package:siargao_genui/theme/app_theme.dart';

/// One golden per catalog component, rendered from the gallery sample
/// through genui. Regenerate with `flutter test --update-goldens test/goldens`.
void main() {
  for (final GallerySample sample in gallerySamples) {
    testWidgets('${sample.component} golden', (tester) async {
      tester.view.physicalSize = const Size(760, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final SurfaceSession session = SurfaceSession()..apply(sample.messages);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const ValueKey('golden'),
                child: Container(
                  width: 760,
                  color: AppColors.page,
                  padding: const EdgeInsets.all(24),
                  child: A2uiSurfaceView(session: session),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('golden')),
        matchesGoldenFile('${sample.component.toLowerCase()}.png'),
      );
    });
  }
}
