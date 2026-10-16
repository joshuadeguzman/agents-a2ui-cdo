import 'package:flutter/material.dart';

import 'a2ui_surface_view.dart';
import 'surface_session.dart';

/// Renders a list of A2UI messages as one surface. Owns its
/// [SurfaceSession] and rebuilds it when [messages] change identity.
class ResponseSurface extends StatefulWidget {
  /// Creates a [ResponseSurface].
  const ResponseSurface({super.key, required this.messages, this.onAction});

  /// Decoded A2UI messages.
  final List<Map<String, Object?>> messages;

  /// Button actions from the surface.
  final void Function(SurfaceAction action)? onAction;

  @override
  State<ResponseSurface> createState() => _ResponseSurfaceState();
}

class _ResponseSurfaceState extends State<ResponseSurface> {
  late SurfaceSession _session;

  @override
  void initState() {
    super.initState();
    _session = _open(widget.messages);
  }

  SurfaceSession _open(List<Map<String, Object?>> messages) =>
      SurfaceSession()..apply(messages);

  @override
  void didUpdateWidget(ResponseSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.messages, widget.messages)) {
      _session.dispose();
      _session = _open(widget.messages);
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return A2uiSurfaceView(session: _session, onAction: widget.onAction);
  }
}
