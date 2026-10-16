import 'package:flutter/material.dart';

import '../config.dart';
import '../services/models.dart';
import '../theme/app_theme.dart';

/// A small rounded label.
class Pill extends StatelessWidget {
  /// Creates a [Pill].
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.background = AppColors.tealSoft,
    this.foreground = AppColors.tealInk,
    this.outlined = false,
  });

  /// Text.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Fill color.
  final Color background;

  /// Text and icon color.
  final Color foreground;

  /// Draw a border instead of a fill.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: outlined ? Colors.white : background,
        borderRadius: BorderRadius.circular(999),
        border: outlined ? Border.all(color: AppColors.line) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: foreground),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: foreground, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// The delivery path label: `A2A`, `MCP resource` or `MCP tool`.
class PathPill extends StatelessWidget {
  /// Creates a [PathPill].
  const PathPill({super.key, required this.path});

  /// The path.
  final DeliveryPath path;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (path) {
      DeliveryPath.a2a => Icons.forum_outlined,
      DeliveryPath.mcpResource => Icons.description_outlined,
      DeliveryPath.mcpTool => Icons.build_outlined,
    };
    return Pill(label: path.label, icon: icon);
  }
}

/// How many model calls produced the surface, for example
/// `0 model calls · template`.
class ModelCallsPill extends StatelessWidget {
  /// Creates a [ModelCallsPill].
  const ModelCallsPill({super.key, required this.meta});

  /// Response metadata, or null while loading.
  final ResponseMeta? meta;

  @override
  Widget build(BuildContext context) {
    final ResponseMeta? m = meta;
    return Pill(
      label: m == null ? 'Waiting for a response' : m.label,
      icon: Icons.memory_rounded,
      outlined: true,
      foreground: AppColors.ink,
    );
  }
}

/// Offline fixtures or Live.
class ModePill extends StatelessWidget {
  /// Creates a [ModePill].
  const ModePill({super.key, required this.mode, this.compact = false});

  /// The mode.
  final DemoMode mode;

  /// Shorter label for narrow screens.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool live = mode == DemoMode.live;
    return Pill(
      label: compact ? (live ? 'Live' : 'Offline') : mode.label,
      icon: live ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
      background: live ? const Color(0xFFDDF3E4) : AppColors.amberSoft,
      foreground: live ? const Color(0xFF14532D) : AppColors.amberInk,
    );
  }
}
