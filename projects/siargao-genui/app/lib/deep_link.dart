import 'package:flutter/foundation.dart';

import 'features/chat/chat_screen.dart';

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
/// `?tab=chat|home|search|gallery&intent=<id>&view=text|a2ui|both`.
@immutable
class DeepLink {
  /// Creates a [DeepLink].
  const DeepLink({this.tab, this.intent, this.view});

  /// Reads the query of [uri] (on web, `Uri.base`).
  factory DeepLink.fromUri(Uri uri) {
    final Map<String, String> q = uri.queryParameters;
    final String? intent = q['intent'];
    return DeepLink(
      tab: AppTab.parse(q['tab']) ?? (intent != null ? AppTab.chat : null),
      intent: (intent == null || intent.isEmpty) ? null : intent,
      view: ChatView.parse(q['view']),
    );
  }

  /// Tab to open.
  final AppTab? tab;

  /// Chat intent to run on open.
  final String? intent;

  /// Chat view.
  final ChatView? view;
}
