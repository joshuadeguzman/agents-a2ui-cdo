import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Which way an entry travelled.
enum WireDirection {
  /// App to server.
  outgoing,

  /// Server to app.
  incoming,
}

/// Where a trace came from.
enum WireChannel {
  /// A2A `message/stream`.
  a2a('A2A'),

  /// MCP `resources/read`.
  mcpResource('MCP resource'),

  /// MCP `tools/call`.
  mcpTool('MCP tool'),

  /// A recorded fixture (offline mode).
  fixture('Fixture');

  const WireChannel(this.label);

  /// Short label for the UI.
  final String label;
}

/// What an entry is.
enum WireKind {
  /// The request the app sent.
  request,

  /// A protocol frame without A2UI in it (A2A status, MCP result).
  frame,

  /// One A2UI message, the thing the renderer applies.
  a2ui,

  /// A plain text answer.
  text,
}

/// How fast the renderer applies A2UI messages while the inspector is open.
enum RenderPace {
  /// As soon as they arrive.
  instant('Instant'),

  /// One message every [WireLog.slowDelay].
  slow('Slow'),

  /// One message per click on "Render next".
  step('Step');

  const RenderPace(this.label);

  /// Label for the pace control.
  final String label;

  /// Parses `pace=` from a deep link.
  static RenderPace? parse(String? value) {
    for (final RenderPace p in RenderPace.values) {
      if (p.name == value) return p;
    }
    return null;
  }
}

/// One line in the inspector.
class WireEntry {
  WireEntry._({
    required this.id,
    required this.trace,
    required this.at,
    required this.direction,
    required this.kind,
    required this.title,
    this.summary,
    this.json,
  }) : bytes = json == null ? 0 : utf8.encode(jsonEncode(json)).length;

  /// Unique id within the log.
  final int id;

  /// The trace this entry belongs to.
  final WireTrace trace;

  /// When the app saw it.
  final DateTime at;

  /// Outgoing or incoming.
  final WireDirection direction;

  /// Request, frame, A2UI message or text.
  final WireKind kind;

  /// For example `createSurface` or `POST message/stream`.
  final String title;

  /// One line description.
  final String? summary;

  /// The payload, shown as pretty JSON.
  final Object? json;

  /// Size of [json] encoded as UTF-8.
  final int bytes;

  /// For A2UI messages: true once the renderer applied it.
  bool rendered = false;

  /// Milliseconds since the trace started.
  int get offsetMs => at.difference(trace.startedAt).inMilliseconds;
}

/// One request and everything that came back for it.
class WireTrace {
  WireTrace._({
    required this.id,
    required this.channel,
    required this.label,
    required this.startedAt,
    required this.textOnly,
  });

  /// Unique id within the log.
  final int id;

  /// A2A, MCP resource, MCP tool or fixture.
  final WireChannel channel;

  /// The prompt, resource URI or tool call.
  final String label;

  /// When the request started.
  final DateTime startedAt;

  /// True for the plain text half of a chat prompt.
  final bool textOnly;

  /// Entries in arrival order.
  final List<WireEntry> entries = [];

  /// Set by the surface that rendered this trace, so the inspector can
  /// replay it.
  VoidCallback? replay;

  /// When the response finished, or null while it is in flight.
  DateTime? finishedAt;

  /// `template` or `model`, from the response metadata.
  String? source;

  /// Model calls the server made for this response.
  int? modelCalls;

  /// Server side time, from the response metadata.
  int? serverMs;

  /// Routed intent, from the response metadata.
  String? intent;

  /// Friendly error, if the request failed.
  String? error;

  /// True until [WireLog.finish] is called.
  bool get inFlight => finishedAt == null;

  /// Request start to finish, as the app saw it.
  int? get roundTripMs => finishedAt?.difference(startedAt).inMilliseconds;

  /// A2UI entries only.
  Iterable<WireEntry> get a2uiEntries =>
      entries.where((e) => e.kind == WireKind.a2ui);
}

/// Everything the app sent and received, for the inspector panel.
///
/// Services record entries as they happen, so timestamps are real arrival
/// times. The [pace] only changes when the renderer applies A2UI messages,
/// never when they arrive.
class WireLog extends ChangeNotifier {
  /// Creates an empty log.
  WireLog({
    this.maxTraces = 60,
    this._open = false,
    this._pace = RenderPace.instant,
  });

  /// Delay between messages in [RenderPace.slow].
  static const Duration slowDelay = Duration(milliseconds: 900);

  /// Oldest traces are dropped past this count.
  final int maxTraces;

  final List<WireTrace> _traces = [];
  final List<Completer<void>> _stepWaiters = [];
  int _nextId = 0;
  bool _disposed = false;

  /// Traces, oldest first.
  List<WireTrace> get traces => List.unmodifiable(_traces);

  bool _open;

  /// Whether the inspector panel is showing.
  bool get open => _open;
  set open(bool value) {
    if (_open == value) return;
    _open = value;
    if (!value) _releaseAll();
    _notify();
  }

  RenderPace _pace;

  /// The pace the user picked. See [effectivePace].
  RenderPace get pace => _pace;
  set pace(RenderPace value) {
    if (_pace == value) return;
    _pace = value;
    if (value != RenderPace.step) _releaseAll();
    _notify();
  }

  /// Pacing only applies while the panel is open, so a closed panel can never
  /// leave a surface waiting for a click nobody can make.
  RenderPace get effectivePace => _open ? _pace : RenderPace.instant;

  bool _showText = false;

  /// Whether to list the plain text half of chat prompts.
  bool get showText => _showText;
  set showText(bool value) {
    if (_showText == value) return;
    _showText = value;
    _notify();
  }

  /// Starts a trace for one request.
  WireTrace begin(WireChannel channel, String label, {bool textOnly = false}) {
    final WireTrace trace = WireTrace._(
      id: _nextId++,
      channel: channel,
      label: label,
      startedAt: DateTime.now(),
      textOnly: textOnly,
    );
    _traces.add(trace);
    if (_traces.length > maxTraces) _traces.removeAt(0);
    _notify();
    return trace;
  }

  /// Adds an entry to [trace] and returns it.
  WireEntry add(
    WireTrace trace,
    WireDirection direction,
    WireKind kind,
    String title, {
    String? summary,
    Object? json,
  }) {
    final WireEntry entry = WireEntry._(
      id: _nextId++,
      trace: trace,
      at: DateTime.now(),
      direction: direction,
      kind: kind,
      title: title,
      summary: summary,
      json: json,
    );
    trace.entries.add(entry);
    _notify();
    return entry;
  }

  /// Marks [trace] done, with what the server said about how it answered.
  void finish(
    WireTrace? trace, {
    String? source,
    int? modelCalls,
    int? serverMs,
    String? intent,
    String? error,
  }) {
    if (trace == null || !trace.inFlight) return;
    trace
      ..finishedAt = DateTime.now()
      ..source = source
      ..modelCalls = modelCalls
      ..serverMs = serverMs
      ..intent = intent
      ..error = error;
    _notify();
  }

  /// True while any request is waiting for its answer.
  bool get anyInFlight => _traces.any((t) => t.inFlight);

  /// Adds one entry per A2UI message and returns them in order.
  List<WireEntry> addA2ui(
    WireTrace trace,
    List<Map<String, Object?>> messages, {
    String? via,
  }) => [
    for (final Map<String, Object?> m in messages)
      add(
        trace,
        WireDirection.incoming,
        WireKind.a2ui,
        a2uiTypeOf(m),
        summary: [summarizeA2ui(m), ?via].join(' · '),
        json: m,
      ),
  ];

  /// Marks an A2UI entry as applied by the renderer.
  void markRendered(WireEntry entry, {bool rendered = true}) {
    if (entry.rendered == rendered) return;
    entry.rendered = rendered;
    _notify();
  }

  /// Waits for the user to press "Render next" in step mode.
  Future<void> waitForStep() {
    final Completer<void> c = Completer<void>();
    _stepWaiters.add(c);
    _notify();
    return c.future;
  }

  /// True when a surface is waiting for "Render next".
  bool get canStep => _stepWaiters.isNotEmpty;

  /// Lets the oldest waiting surface apply its next message.
  void step() {
    if (_stepWaiters.isEmpty) return;
    _stepWaiters.removeAt(0).complete();
    _notify();
  }

  void _releaseAll() {
    for (final Completer<void> c in _stepWaiters) {
      c.complete();
    }
    _stepWaiters.clear();
  }

  /// Removes every trace.
  void clear() {
    _traces.clear();
    _notify();
  }

  bool _notifyScheduled = false;

  /// Notifies now, or after the frame when called while widgets build (a
  /// surface marks entries rendered from its build).
  void _notify() {
    if (_disposed) return;
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (!_disposed) notifyListeners();
      });
      SchedulerBinding.instance.ensureVisualUpdate();
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _releaseAll();
    super.dispose();
  }
}

/// The A2UI message type: `createSurface`, `updateComponents`, ...
String a2uiTypeOf(Map<String, Object?> message) {
  for (final String key in const [
    'createSurface',
    'updateComponents',
    'updateDataModel',
    'deleteSurface',
  ]) {
    if (message.containsKey(key)) return key;
  }
  return 'unknown message';
}

/// A one line description of an A2UI message for the inspector.
String summarizeA2ui(Map<String, Object?> message) {
  final Object? body = message[a2uiTypeOf(message)];
  if (body is! Map) return '';
  switch (a2uiTypeOf(message)) {
    case 'createSurface':
      final String catalog = '${body['catalogId'] ?? ''}'
          .split('/')
          .reversed
          .take(2)
          .toList()
          .reversed
          .join('/');
      return 'surface ${body['surfaceId']} · catalog $catalog';
    case 'updateComponents':
      final List<Object?> components =
          (body['components'] as List<Object?>?) ?? const [];
      final Set<String> types = {
        for (final Object? c in components)
          if (c is Map && c['component'] is String) c['component'] as String,
      };
      return '${components.length} components: ${types.join(', ')}';
    case 'updateDataModel':
      final Object? value = body['value'];
      final String keys = value is Map ? value.keys.join(', ') : '$value';
      return 'path ${body['path'] ?? '/'} · $keys';
    default:
      return 'surface ${body['surfaceId']}';
  }
}
