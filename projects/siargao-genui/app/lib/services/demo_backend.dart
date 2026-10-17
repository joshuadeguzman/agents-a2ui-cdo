import '../a2ui/a2ui_surface_view.dart';
import '../config.dart';
import '../inspector/wire_log.dart';
import 'a2a_service.dart';
import 'fixture_service.dart';
import 'mcp_service.dart';
import 'models.dart';
import 'offline_stays.dart';

/// Thrown offline when a typed prompt matches none of the demo intents.
class OfflineNoMatch implements Exception {
  /// Creates an [OfflineNoMatch].
  const OfflineNoMatch();
}

/// The MCP resource for the Home tab.
const String homeResourceUri = 'a2ui://home/first-run';

/// The MCP tool for the Search tab.
const String searchToolName = 'search_stays';

/// Where the screens get surfaces from. One implementation per [DemoMode].
abstract class DemoBackend {
  /// Picks the backend for [config].
  factory DemoBackend.forConfig(
    AppConfig config, {
    FixtureService? fixtures,
    WireLog? wire,
  }) => config.isLive
      ? LiveBackend(
          a2a: A2aService(agentUrl: config.agentUrl, wire: wire),
          mcp: McpService(mcpUrl: config.mcpUrl, wire: wire),
        )
      : OfflineBackend(fixtures ?? FixtureService(), wire: wire);

  /// True for live services.
  bool get isLive;

  /// A chat answer as A2UI or as markdown text.
  Future<SurfaceResponse> chat({
    required String prompt,
    String? intent,
    required ResponseFormat format,
  });

  /// The Home surface (MCP resource).
  Future<SurfaceResponse> home();

  /// The Search surface (MCP tool).
  Future<SurfaceResponse> searchStays(StayQuery query);

  /// Handles a button action. Returns a short message for the UI, and
  /// optionally a new surface.
  Future<SurfaceResponse> sendAction(SurfaceAction action);
}

/// Matches a typed prompt to a demo intent by keywords, like the agent does
/// before it falls back to the model. Returns null when nothing matches.
String? routeOfflineIntent(String prompt) {
  final String p = prompt.toLowerCase();
  if (p.contains('flight') || p.contains('fly ') || p.contains('fare')) {
    return 'flights_under_8000';
  }
  if (p.contains('surf') || p.contains('wave')) return 'surf_this_week';
  if (p.contains('been') ||
      p.contains('flexible') ||
      p.contains('returning') ||
      p.contains('again')) {
    return 'returning_flexible';
  }
  if (p.contains('first') ||
      p.contains('plan') ||
      p.contains('itinerary') ||
      p.contains('trip')) {
    return 'first_time_trip';
  }
  return null;
}

/// Offline mode: everything comes from bundled fixtures.
class OfflineBackend implements DemoBackend {
  /// Creates an [OfflineBackend].
  OfflineBackend(this.fixtures, {this.wire});

  /// Fixture loader.
  final FixtureService fixtures;

  /// Records fixture reads for the inspector, if set.
  final WireLog? wire;

  /// Logs a fixture read and its A2UI messages (or its text answer).
  SurfaceResponse _traced(
    WireChannel channel,
    String label,
    String fixture,
    SurfaceResponse r, {
    bool textOnly = false,
    String via = 'recorded fixture',
  }) {
    final WireLog? log = wire;
    if (log == null) return r;
    final WireTrace trace = log.begin(channel, label, textOnly: textOnly);
    log.add(
      trace,
      WireDirection.outgoing,
      WireKind.request,
      'read $fixture',
      summary: 'Offline: no network, recorded ${channel.label} answer',
    );
    final List<WireEntry> entries = r.hasSurface
        ? log.addA2ui(trace, r.messages, via: via)
        : const [];
    if (!r.hasSurface && r.text != null) {
      log.add(
        trace,
        WireDirection.incoming,
        WireKind.text,
        'text answer',
        summary: '${r.text!.length} characters of markdown',
        json: {'text': r.text},
      );
    }
    finishTrace(log, trace, meta: r.meta);
    return SurfaceResponse(
      path: r.path,
      messages: r.messages,
      text: r.text,
      meta: r.meta,
      note: r.note,
      trace: trace,
      entries: entries,
    );
  }

  @override
  bool get isLive => false;

  @override
  Future<SurfaceResponse> chat({
    required String prompt,
    String? intent,
    required ResponseFormat format,
  }) async {
    final String? resolved = intent ?? routeOfflineIntent(prompt);
    if (resolved == null) throw const OfflineNoMatch();
    final Fixture f = await fixtures.load(resolved);
    final String? note = intent == null
        ? 'Offline: matched your words to "${f.title}".'
        : null;
    final SurfaceResponse r = switch (format) {
      ResponseFormat.a2ui => SurfaceResponse(
        path: f.path,
        messages: f.messages,
        meta: f.meta,
        note: note,
      ),
      ResponseFormat.text => SurfaceResponse(
        path: f.path,
        text: f.text,
        meta: f.meta,
        note: note,
      ),
    };
    return _traced(
      WireChannel.fixture,
      prompt,
      'fixtures/$resolved.json',
      r,
      textOnly: format == ResponseFormat.text,
    );
  }

  @override
  Future<SurfaceResponse> home() async {
    final Fixture f = await fixtures.load('home_first_run');
    return _traced(
      WireChannel.fixture,
      homeResourceUri,
      'fixtures/home_first_run.json',
      SurfaceResponse(path: f.path, messages: f.messages, meta: f.meta),
    );
  }

  @override
  Future<SurfaceResponse> searchStays(StayQuery query) async {
    final Fixture f = await fixtures.load('stays_near_cloud9');
    final String label =
        '$searchToolName(${query.toArguments().entries.map((e) => '${e.key}: ${e.value}').join(', ')})';
    if (query == StayQuery.fixtureDefault) {
      return _traced(
        WireChannel.fixture,
        label,
        'fixtures/stays_near_cloud9.json',
        SurfaceResponse(
          path: f.path,
          messages: f.messages,
          meta: f.meta,
          text: f.text,
        ),
      );
    }
    final List<Stay> results = filterStays(await fixtures.stays(), query);
    return _traced(
      WireChannel.fixture,
      label,
      'fixtures/stays_near_cloud9.json',
      SurfaceResponse(
        path: f.path,
        messages: buildStaysMessages(f, results, query),
        meta: f.meta,
        note:
            'Offline: filtered the sample stays on this device with the '
            'search_stays rule.',
      ),
      via: 'filled on this device',
    );
  }

  @override
  Future<SurfaceResponse> sendAction(SurfaceAction action) async {
    return SurfaceResponse(
      path: DeliveryPath.a2a,
      text: describeAction(action),
    );
  }
}

/// A one line description of an action for the offline SnackBar.
String describeAction(SurfaceAction action) {
  final String details = action.context.entries
      .map((e) => '${e.key}: ${e.value}')
      .join(', ');
  final String ctx = details.isEmpty ? '' : ' ($details)';
  return 'Offline demo: "${action.name}" from ${action.sourceComponentId}$ctx. '
      'In live mode this goes to the agent.';
}

/// Live mode: Chat over A2A, Home and Search over MCP.
class LiveBackend implements DemoBackend {
  /// Creates a [LiveBackend].
  LiveBackend({required this.a2a, required this.mcp});

  /// Agent client.
  final A2aService a2a;

  /// MCP client.
  final McpService mcp;

  @override
  bool get isLive => true;

  @override
  Future<SurfaceResponse> chat({
    required String prompt,
    String? intent,
    required ResponseFormat format,
  }) async {
    final AgentReply reply = await a2a.sendPrompt(
      prompt: prompt,
      intent: intent,
      format: format,
    );
    if (format == ResponseFormat.a2ui && reply.messages.isEmpty) {
      if (reply.text != null) {
        return SurfaceResponse(
          path: DeliveryPath.a2a,
          text: reply.text,
          meta: reply.meta,
          note: 'The agent answered with text only.',
          trace: reply.trace,
        );
      }
      throw const A2aException('The agent sent no surface.');
    }
    return SurfaceResponse(
      path: DeliveryPath.a2a,
      messages: format == ResponseFormat.a2ui ? reply.messages : const [],
      text: reply.text,
      meta: reply.meta,
      trace: reply.trace,
      entries: format == ResponseFormat.a2ui ? reply.entries : const [],
    );
  }

  @override
  Future<SurfaceResponse> home() => mcp.readResource(homeResourceUri);

  @override
  Future<SurfaceResponse> searchStays(StayQuery query) =>
      mcp.callTool(searchToolName, query.toArguments());

  @override
  Future<SurfaceResponse> sendAction(SurfaceAction action) async {
    final AgentReply reply = await a2a.sendAction(action);
    return SurfaceResponse(
      path: DeliveryPath.a2a,
      messages: reply.messages,
      text: reply.text ?? 'Sent "${action.name}" to the agent.',
      meta: reply.meta,
      trace: reply.trace,
      entries: reply.entries,
    );
  }
}
