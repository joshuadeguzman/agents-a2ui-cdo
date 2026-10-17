import 'package:flutter/foundation.dart';

import 'features/chat/chat_screen.dart';
import 'inspector/wire_log.dart';

/// Main tabs plus the gallery.
enum AppTab {
  /// Chat (A2A).
  chat,

  /// Home (MCP resource).
  home,

  /// Search (MCP tool).
  search,

  /// Widget gallery (not a main tab).
  gallery;

  /// Parses `tab=`.
  static AppTab? parse(String? value) {
    for (final AppTab t in AppTab.values) {
      if (t.name == value) return t;
    }
    return null;
  }
}

/// Query parameters for deterministic screenshots and demos:
/// `?tab=chat|home|search|gallery&intent=<id>&view=text|a2ui|both`, plus
/// `inspect=1` to open the A2UI stream inspector and `pace=slow|step`.
@immutable
class DeepLink {
  /// Creates a [DeepLink].
  const DeepLink({
    this.tab,
    this.intent,
    this.view,
    this.inspect = false,
    this.pace,
  });

  /// Reads the query of [uri] (on web, `Uri.base`).
  factory DeepLink.fromUri(Uri uri) {
    final Map<String, String> q = uri.queryParameters;
    final String? intent = q['intent'];
    return DeepLink(
      tab: AppTab.parse(q['tab']) ?? (intent != null ? AppTab.chat : null),
      intent: (intent == null || intent.isEmpty) ? null : intent,
      view: ChatView.parse(q['view']),
      inspect: const {'1', 'true', 'yes', 'on'}.contains(q['inspect']),
      pace: RenderPace.parse(q['pace']),
    );
  }

  /// Tab to open.
  final AppTab? tab;

  /// Chat intent to run on open.
  final String? intent;

  /// Chat view.
  final ChatView? view;

  /// Open the A2UI stream inspector on start.
  final bool inspect;

  /// Initial render pace for the inspector.
  final RenderPace? pace;
}
