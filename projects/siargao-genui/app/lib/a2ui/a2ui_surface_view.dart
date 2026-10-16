import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

import 'surface_session.dart';

/// A user action from a surface, in the shape docs/CONTRACT.md sends to the
/// agent: `{name, sourceComponentId, surfaceId, context, timestamp}`.
@immutable
class SurfaceAction {
  /// Creates a [SurfaceAction].
  const SurfaceAction({
    required this.name,
    required this.sourceComponentId,
    required this.surfaceId,
    required this.context,
    required this.timestamp,
  });

  /// Builds an action from a genui [UiEvent].
  factory SurfaceAction.fromEvent(UiEvent event, String surfaceId) {
    final Map<String, Object?> m = event.toMap();
    final Object? ctx = m['context'];
    return SurfaceAction(
      name: m['name']?.toString() ?? '',
      sourceComponentId: m['sourceComponentId']?.toString() ?? '',
      surfaceId: surfaceId,
      context: ctx is Map ? ctx.cast<String, Object?>() : const {},
      timestamp: m['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  /// Event name, for example `choose_stay`.
  final String name;

  /// Id of the component that fired it.
  final String sourceComponentId;

  /// Surface id.
  final String surfaceId;

  /// Resolved event context.
  final Map<String, Object?> context;

  /// ISO 8601 timestamp.
  final String timestamp;

  /// The `action` object for the A2A DataPart.
  Map<String, Object?> toJson() => {
    'name': name,
    'sourceComponentId': sourceComponentId,
    'surfaceId': surfaceId,
    'context': context,
    'timestamp': timestamp,
  };
}

/// Routes user actions to a callback instead of the controller's `onSubmit`.
class _CallbackActionDelegate implements ActionDelegate {
  const _CallbackActionDelegate(this.onAction);

  final void Function(SurfaceAction action)? onAction;

  @override
  bool handleEvent(
    BuildContext context,
    UiEvent event,
    SurfaceContext genUiContext,
    Widget Function(SurfaceDefinition, Catalog, String, DataContext)
    buildWidget,
  ) {
    if (!event.isUserAction) return true;
    onAction?.call(SurfaceAction.fromEvent(event, genUiContext.surfaceId));
    return true;
  }
}

/// Renders the surface of a [SurfaceSession] with the Siargao catalog.
class A2uiSurfaceView extends StatelessWidget {
  /// Creates an [A2uiSurfaceView].
  const A2uiSurfaceView({super.key, required this.session, this.onAction});

  /// The session holding the surface.
  final SurfaceSession session;

  /// Called when the user taps a button in the surface.
  final void Function(SurfaceAction action)? onAction;

  @override
  Widget build(BuildContext context) {
    final SurfaceContext? surfaceContext = session.context;
    if (surfaceContext == null) return const SizedBox.shrink();
    return Surface(
      key: ValueKey(session),
      surfaceContext: surfaceContext,
      actionDelegate: _CallbackActionDelegate(onAction),
    );
  }
}
