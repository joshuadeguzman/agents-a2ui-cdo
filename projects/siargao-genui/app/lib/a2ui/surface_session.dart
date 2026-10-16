import 'dart:async';
import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart' as core;
import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';

import '../catalog/siargao_catalog.dart';
import 'surface_sanitizer.dart';

/// Owns one genui [SurfaceController] for one response, applies A2UI
/// messages to it safely, and keeps renderer errors local.
///
/// genui's `SurfaceController.reportError` puts errors on `onSubmit`, which an
/// app would normally forward to the agent. This session only records them
/// in [errors] and logs them. Nothing is sent anywhere automatically, in
/// offline or live mode. User actions are handled by the `Surface` action
/// delegate instead (see `A2uiSurfaceView`).
class SurfaceSession {
  /// Creates a session with the Siargao catalog (or [catalog] in tests).
  SurfaceSession({Catalog? catalog})
    : catalog = catalog ?? siargaoCatalog,
      controller = SurfaceController(catalogs: [catalog ?? siargaoCatalog]) {
    _submissions = controller.onSubmit.listen(_onSubmit);
  }

  /// The catalog used to render.
  final Catalog catalog;

  /// The genui controller.
  final SurfaceController controller;

  late final StreamSubscription<ChatMessage> _submissions;

  /// Renderer and validation errors, newest last. Never sent to a server.
  final ValueNotifier<List<String>> errors = ValueNotifier(const []);

  /// Components dropped because their type is not in the catalog.
  final List<String> skipped = [];

  /// The surface id from the first `createSurface` message.
  String? surfaceId;

  bool _disposed = false;

  /// Applies raw A2UI messages (decoded JSON maps) in order.
  void apply(List<Object?> messages) {
    if (_disposed) return;
    final SanitizeResult clean = sanitizeMessages(
      messages,
      catalog.items.map((i) => i.name).toSet(),
    );
    if (clean.skipped.isNotEmpty) {
      skipped.addAll(clean.skipped);
      debugPrint('Skipped unknown components: ${clean.skipped.join(', ')}');
    }
    for (final Map<String, Object?> json in clean.messages) {
      final core.A2uiMessage message;
      try {
        message = core.A2uiMessage.fromJson(json.cast<String, dynamic>());
      } catch (error) {
        _record('Could not read an A2UI message: $error');
        continue;
      }
      if (message is core.CreateSurfaceMessage) {
        surfaceId ??= message.surfaceId;
      }
      controller.handleMessage(message);
    }
  }

  /// The context the `Surface` widget renders, or null before
  /// `createSurface` arrived.
  SurfaceContext? get context {
    final String? id = surfaceId;
    if (id == null || _disposed) return null;
    return controller.contextFor(id);
  }

  /// A snapshot of the surface data model, for debugging and tests.
  Object? dataAt(String path) {
    final SurfaceContext? ctx = context;
    if (ctx == null) return null;
    return ctx.dataModel.getValue<Object?>(DataPath(path));
  }

  void _onSubmit(ChatMessage message) {
    // Only errors reach here: actions are handled by the action delegate.
    for (final StandardPart part in message.parts) {
      if (part.isUiInteractionPart) {
        _record(part.asUiInteractionPart!.interaction);
      }
    }
  }

  void _record(String error) {
    if (_disposed) return;
    String text = error;
    try {
      final Object? decoded = jsonDecode(error);
      if (decoded is Map && decoded['error'] is Map) {
        text = (decoded['error'] as Map)['message']?.toString() ?? error;
      }
    } catch (_) {
      // Not JSON; keep the raw text.
    }
    debugPrint('A2UI renderer error (kept local, not sent): $text');
    errors.value = [...errors.value, text];
  }

  /// Releases the controller.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_submissions.cancel());
    controller.dispose();
    errors.dispose();
  }
}
