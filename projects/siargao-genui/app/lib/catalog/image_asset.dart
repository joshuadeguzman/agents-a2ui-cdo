import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'catalog_schemas.g.dart';

/// Maps image keys from catalog/images.json to bundled assets at
/// `assets/img/<key>.jpg` (then `.png`, then `.webp`).
///
/// The asset manifest is read once at startup. Until then, and for keys with
/// no file, [SiargaoImage] shows a placeholder, so a missing file never throws.
class ImageAssets {
  ImageAssets._();

  static const List<String> _extensions = ['jpg', 'png', 'webp'];
  static final ValueNotifier<Set<String>> _available = ValueNotifier(
    const <String>{},
  );

  /// Notifies when the manifest has loaded.
  static ValueListenable<Set<String>> get available => _available;

  /// Loads the asset manifest. Safe to call more than once.
  static Future<void> load([AssetBundle? bundle]) async {
    try {
      final AssetManifest manifest = await AssetManifest.loadFromAssetBundle(
        bundle ?? rootBundle,
      );
      _available.value = manifest
          .listAssets()
          .where((a) => a.startsWith('assets/img/'))
          .toSet();
    } catch (error) {
      debugPrint('Image manifest unavailable, using placeholders: $error');
    }
  }

  /// Replaces the known asset set. For tests.
  @visibleForTesting
  static void debugSetAvailable(Set<String> assets) {
    _available.value = assets;
  }

  /// The asset path for [key], or null when no file exists.
  static String? pathFor(String? key) {
    if (key == null || key.isEmpty) return null;
    // Keys are plain names. Never treat a URL or a path as a key.
    if (key.contains('/') || key.contains(':')) return null;
    for (final String ext in _extensions) {
      final String p = 'assets/img/$key.$ext';
      if (_available.value.contains(p)) return p;
    }
    return null;
  }

  /// Alt text for [key] from catalog/images.json.
  static String altFor(String? key) =>
      siargaoImageAlt[key] ?? 'Photo of Siargao Island';
}

/// An image by key with a fixed aspect ratio and a tasteful placeholder.
class SiargaoImage extends StatelessWidget {
  /// Creates a [SiargaoImage].
  const SiargaoImage({
    super.key,
    required this.imageKey,
    required this.aspectRatio,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.card)),
    this.showAlt = true,
  });

  /// Key from catalog/images.json.
  final String? imageKey;

  /// Width divided by height, for example 16 / 9.
  final double aspectRatio;

  /// Corner rounding.
  final BorderRadius borderRadius;

  /// Whether the placeholder shows the alt text.
  final bool showAlt;

  @override
  Widget build(BuildContext context) {
    final String alt = ImageAssets.altFor(imageKey);
    return Semantics(
      image: true,
      label: alt,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: ValueListenableBuilder<Set<String>>(
            valueListenable: ImageAssets.available,
            builder: (context, _, _) {
              final String? path = ImageAssets.pathFor(imageKey);
              final Widget placeholder = ImagePlaceholder(
                imageKey: imageKey,
                alt: showAlt ? alt : null,
              );
              if (path == null) return placeholder;
              return Image.asset(
                path,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (context, error, stack) => placeholder,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Soft gradient with a subtle icon and the alt text, used when an image file
/// is missing. Deterministic per key so goldens stay stable.
class ImagePlaceholder extends StatelessWidget {
  /// Creates an [ImagePlaceholder].
  const ImagePlaceholder({super.key, this.imageKey, this.alt});

  /// Image key, used to pick a gradient and an icon.
  final String? imageKey;

  /// Alt text to show, or null to hide it.
  final String? alt;

  static const List<List<Color>> _gradients = [
    [Color(0xFFCFEDEE), Color(0xFF9ED3D6)], // shallow water
    [Color(0xFFD9EFE6), Color(0xFFA9D8C6)], // lagoon
    [Color(0xFFF6EEDF), Color(0xFFE6D3B3)], // sand
    [Color(0xFFDDEBF6), Color(0xFFADCBE6)], // sky
    [Color(0xFFF7E6DD), Color(0xFFEBC3AE)], // sunset
  ];

  IconData get _icon {
    final String k = imageKey ?? '';
    if (k.contains('flight')) return Icons.flight_takeoff_rounded;
    if (k.startsWith('stay-')) return Icons.cottage_outlined;
    if (k.contains('river') || k.contains('lagoon') || k.contains('pools')) {
      return Icons.water_outlined;
    }
    if (k.contains('beach') || k.contains('boardwalk')) {
      return Icons.surfing_rounded;
    }
    if (k.contains('island')) return Icons.beach_access_outlined;
    return Icons.landscape_outlined;
  }

  int get _seed {
    final String k = imageKey ?? '';
    var h = 0;
    for (final int c in k.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> colors = _gradients[_seed % _gradients.length];
    final TextStyle? altStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: const Color(0xFF2E3D3F), fontSize: 13, height: 1.35);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Icon(
              _icon,
              size: 44,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          if (alt != null)
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Text(
                alt!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: altStyle,
              ),
            ),
        ],
      ),
    );
  }
}
