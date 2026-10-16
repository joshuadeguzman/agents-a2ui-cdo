import 'package:flutter/foundation.dart';

import '../../services/demo_backend.dart';
import '../../services/models.dart';
import '../../widgets/status_panels.dart';

/// Loading, loaded or failed.
@immutable
class Slot {
  const Slot._({this.response, this.error, this.loading = false});

  /// Still waiting.
  const Slot.loading() : this._(loading: true);

  /// Loaded.
  const Slot.data(SurfaceResponse response) : this._(response: response);

  /// Failed with a friendly message.
  const Slot.error(String message) : this._(error: message);

  /// The response once loaded.
  final SurfaceResponse? response;

  /// Friendly error text.
  final String? error;

  /// True while waiting.
  final bool loading;
}

/// One prompt and both of its answers.
class ChatTurn {
  /// Creates a [ChatTurn].
  ChatTurn({required this.id, required this.prompt, this.intent});

  /// Unique id within the chat.
  final int id;

  /// What the user asked.
  final String prompt;

  /// Intent when a demo chip was used.
  final String? intent;

  /// The A2UI answer.
  Slot a2ui = const Slot.loading();

  /// The plain text answer.
  Slot text = const Slot.loading();
}

/// Holds the conversation and sends both requests (A2UI and text) for each
/// prompt, so the toggle can switch instantly.
class ChatController extends ChangeNotifier {
  /// Creates a [ChatController].
  ChatController(this._backend);

  final DemoBackend _backend;
  final List<ChatTurn> _turns = [];
  int _nextId = 0;
  bool _disposed = false;

  /// Turns, oldest first.
  List<ChatTurn> get turns => List.unmodifiable(_turns);

  /// The newest turn, or null.
  ChatTurn? get latest => _turns.isEmpty ? null : _turns.last;

  /// Sends [prompt]. Pass [intent] for demo chips.
  Future<void> send(String prompt, {String? intent}) async {
    final String trimmed = prompt.trim();
    if (trimmed.isEmpty) return;
    final ChatTurn turn = ChatTurn(
      id: _nextId++,
      prompt: trimmed,
      intent: intent,
    );
    _turns.add(turn);
    _notify();
    await Future.wait([
      _load(turn, ResponseFormat.a2ui),
      _load(turn, ResponseFormat.text),
    ]);
  }

  /// Adds a surface the agent sent in reply to a button action.
  void addAgentSurface(String label, SurfaceResponse response) {
    final ChatTurn turn = ChatTurn(id: _nextId++, prompt: label)
      ..a2ui = Slot.data(response)
      ..text = Slot.data(response);
    _turns.add(turn);
    _notify();
  }

  Future<void> _load(ChatTurn turn, ResponseFormat format) async {
    Slot slot;
    try {
      final SurfaceResponse r = await _backend.chat(
        prompt: turn.prompt,
        intent: turn.intent,
        format: format,
      );
      slot = Slot.data(r);
    } catch (error) {
      slot = Slot.error(friendlyError(error));
    }
    if (format == ResponseFormat.a2ui) {
      turn.a2ui = slot;
    } else {
      turn.text = slot;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
