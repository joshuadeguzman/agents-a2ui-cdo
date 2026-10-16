/// App configuration from `--dart-define` values (see docs/CONTRACT.md).
library;

/// Where surfaces come from.
enum DemoMode {
  /// Read recorded fixtures from `assets/fixtures/`. No network.
  offline,

  /// Call the A2A agent and the MCP server.
  live;

  /// Parses a `DEMO_MODE` value. Anything other than `live` is offline.
  static DemoMode parse(String value) =>
      value.trim().toLowerCase() == 'live' ? DemoMode.live : DemoMode.offline;

  /// Short label shown in the app bar.
  String get label => switch (this) {
    DemoMode.offline => 'Offline fixtures',
    DemoMode.live => 'Live',
  };
}

/// Immutable app configuration.
class AppConfig {
  /// Creates a configuration. Defaults match docs/CONTRACT.md.
  const AppConfig({
    this.mode = DemoMode.offline,
    this.agentUrl = defaultAgentUrl,
    this.mcpUrl = defaultMcpUrl,
  });

  /// Reads `DEMO_MODE`, `AGENT_URL` and `MCP_URL` from `--dart-define`.
  factory AppConfig.fromEnvironment() => AppConfig(
    mode: DemoMode.parse(
      const String.fromEnvironment('DEMO_MODE', defaultValue: 'offline'),
    ),
    agentUrl: const String.fromEnvironment(
      'AGENT_URL',
      defaultValue: defaultAgentUrl,
    ),
    mcpUrl: const String.fromEnvironment(
      'MCP_URL',
      defaultValue: defaultMcpUrl,
    ),
  );

  /// Default A2A base URL.
  static const String defaultAgentUrl = 'http://localhost:10002';

  /// Default MCP endpoint.
  static const String defaultMcpUrl = 'http://localhost:10003/mcp';

  /// Offline fixtures or live services.
  final DemoMode mode;

  /// A2A base URL of the agent.
  final String agentUrl;

  /// MCP Streamable HTTP endpoint.
  final String mcpUrl;

  /// True when the app calls real services.
  bool get isLive => mode == DemoMode.live;
}
