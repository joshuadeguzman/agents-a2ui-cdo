import 'package:flutter/material.dart';

import '../services/a2a_service.dart';
import '../services/demo_backend.dart';
import '../services/mcp_service.dart';
import '../theme/app_theme.dart';

/// A friendly sentence for an error from a backend call.
String friendlyError(Object error) => switch (error) {
  OfflineNoMatch() =>
    'Offline mode only knows the four demo prompts. Tap one of the chips, '
        'or run the app with DEMO_MODE=live to ask anything.',
  A2aException(:final message) => message,
  McpException(:final message) => message,
  _ => 'Something went wrong while loading this. Please try again.',
};

/// Inline error message with an optional retry button. Never a crash.
class ErrorPanel extends StatelessWidget {
  /// Creates an [ErrorPanel].
  const ErrorPanel({super.key, required this.message, this.onRetry});

  /// What went wrong, in plain words.
  final String message;

  /// Retry callback.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gaps.xl - 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.amberInk),
            const SizedBox(width: Gaps.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: t.bodyLarge?.copyWith(color: AppColors.ink),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: Gaps.md),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading indicator with a short label.
class LoadingPanel extends StatelessWidget {
  /// Creates a [LoadingPanel].
  const LoadingPanel({super.key, this.label = 'Loading'});

  /// What is loading.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gaps.xl),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: Gaps.md),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// A small muted line of context, for example how offline data was made.
class NoteLine extends StatelessWidget {
  /// Creates a [NoteLine].
  const NoteLine({super.key, required this.text});

  /// The note.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.inkMuted),
          ),
        ),
      ],
    );
  }
}
