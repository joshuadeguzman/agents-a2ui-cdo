import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'a2ui/a2ui_surface_view.dart';
import 'config.dart';
import 'services/demo_backend.dart';
import 'services/models.dart';
import 'widgets/status_panels.dart';

/// Makes the config and the backend available to every screen.
class AppScope extends InheritedWidget {
  /// Creates an [AppScope].
  const AppScope({
    super.key,
    required this.config,
    required this.backend,
    required super.child,
  });

  /// App configuration.
  final AppConfig config;

  /// Surface source for the current mode.
  final DemoBackend backend;

  /// The nearest scope.
  static AppScope of(BuildContext context) {
    final AppScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above $context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      config != oldWidget.config || backend != oldWidget.backend;
}

/// Sends a surface button action and shows the outcome in a SnackBar.
///
/// Offline the SnackBar describes the action and its context. Live the action
/// goes to the agent and its short reply is shown. Returns the reply so a
/// screen can show a new surface if the agent sent one.
Future<SurfaceResponse?> handleSurfaceAction(
  BuildContext context,
  SurfaceAction action,
) async {
  final DemoBackend backend = AppScope.of(context).backend;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final double screenWidth = MediaQuery.sizeOf(context).width;
  SurfaceResponse? reply;
  String text;
  try {
    reply = await backend.sendAction(action);
    text = reply.text ?? 'Done.';
  } catch (error) {
    text = friendlyError(error);
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 5),
        width: math.min(560, screenWidth - 32),
      ),
    );
  return reply;
}
