import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'config.dart';
import 'deep_link.dart';
import 'features/chat/chat_screen.dart';
import 'features/gallery/gallery_screen.dart';
import 'features/home/home_screen.dart';
import 'features/search/search_screen.dart';
import 'inspector/inspector_panel.dart';
import 'inspector/wire_log.dart';
import 'services/demo_backend.dart';
import 'theme/app_theme.dart';
import 'widgets/badges.dart';

/// The Siargao planner app.
class SiargaoApp extends StatefulWidget {
  /// Creates the app.
  const SiargaoApp({
    super.key,
    required this.config,
    this.link = const DeepLink(),
    this.backend,
    this.wire,
  });

  /// Configuration from `--dart-define`.
  final AppConfig config;

  /// Deep link from the URL.
  final DeepLink link;

  /// Backend override for tests.
  final DemoBackend? backend;

  /// Inspector log override for tests. Pass the same log to [backend].
  final WireLog? wire;

  @override
  State<SiargaoApp> createState() => _SiargaoAppState();
}

class _SiargaoAppState extends State<SiargaoApp> {
  late final WireLog _wire =
      widget.wire ??
      WireLog(
        open: widget.link.inspect,
        pace: widget.link.pace ?? RenderPace.instant,
      );
  late final DemoBackend _backend =
      widget.backend ?? DemoBackend.forConfig(widget.config, wire: _wire);

  @override
  void dispose() {
    if (widget.wire == null) _wire.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      config: widget.config,
      backend: _backend,
      wire: _wire,
      child: MaterialApp(
        title: 'Siargao Planner',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: AppShell(link: widget.link),
      ),
    );
  }
}

/// Width at which the NavigationRail replaces the NavigationBar.
const double railBreakpoint = 900;

/// Width at which the inspector sits beside the app instead of below it.
const double inspectorSideBreakpoint = 1100;

/// Tabs with a NavigationBar (narrow) or NavigationRail (wide), plus the
/// gallery reachable from the app bar.
class AppShell extends StatefulWidget {
  /// Creates the shell.
  const AppShell({super.key, this.link = const DeepLink()});

  /// Deep link from the URL.
  final DeepLink link;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<AppTab> _tabs = [AppTab.chat, AppTab.home, AppTab.search];

  late int _index = switch (widget.link.tab) {
    AppTab.home => 1,
    AppTab.search => 2,
    _ => 0,
  };
  late bool _gallery = widget.link.tab == AppTab.gallery;
  late final Set<int> _visited = {_index};

  /// Keeps the tabs' state when the inspector opens or closes and the layout
  /// around them changes.
  final GlobalKey _pageKey = GlobalKey(debugLabel: 'page');

  void _select(int i) => setState(() {
    _index = i;
    _gallery = false;
    _visited.add(i);
  });

  Widget _tabBody(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    return switch (_tabs[i]) {
      AppTab.chat => ChatScreen(
        initialIntent: widget.link.intent,
        initialView: widget.link.view,
      ),
      AppTab.home => const HomeScreen(),
      AppTab.search => const SearchScreen(),
      AppTab.gallery => const GalleryScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final WireLog wire = AppScope.of(context).wire;
    return ListenableBuilder(
      listenable: wire,
      builder: (context, _) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.pageDown): wire.step,
          const SingleActivator(LogicalKeyboardKey.arrowRight): wire.step,
        },
        child: Focus(autofocus: true, child: _scaffold(context, wire)),
      ),
    );
  }

  Widget _scaffold(BuildContext context, WireLog wire) {
    final AppScope scope = AppScope.of(context);
    final Size screen = MediaQuery.sizeOf(context);
    final bool wide = screen.width >= railBreakpoint;
    final bool inspectorSide = screen.width >= inspectorSideBreakpoint;
    final Widget tabs = IndexedStack(
      index: _index,
      children: [for (var i = 0; i < _tabs.length; i++) _tabBody(i)],
    );
    final Widget page = KeyedSubtree(
      key: _pageKey,
      child: _gallery ? const GalleryScreen() : tabs,
    );
    final Widget panel = InspectorPanel(onClose: () => wire.open = false);
    final Widget content = !wire.open
        ? page
        : inspectorSide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: page),
              SizedBox(
                width: (screen.width * 0.34).clamp(380, 520),
                child: panel,
              ),
            ],
          )
        : LayoutBuilder(
            builder: (context, c) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: page),
                SizedBox(height: c.maxHeight * 0.46, child: panel),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: wide ? Gaps.xl : Gaps.lg,
        leading: _gallery
            ? IconButton(
                tooltip: 'Back',
                onPressed: () => setState(() => _gallery = false),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            // On phones the back button takes the logo's room.
            if (wide || !_gallery) ...[
              const Icon(Icons.waves_rounded, color: AppColors.teal, size: 28),
              const SizedBox(width: Gaps.sm),
            ],
            Flexible(
              child: Text(
                'Siargao Planner',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        actions: [
          ModePill(mode: scope.config.mode, compact: !wide),
          const SizedBox(width: Gaps.sm),
          _InspectorToggle(
            open: wire.open,
            compact: !wide,
            onPressed: () => wire.open = !wire.open,
          ),
          const SizedBox(width: Gaps.xs),
          IconButton(
            tooltip: 'Widget gallery',
            isSelected: _gallery,
            onPressed: () => setState(() => _gallery = !_gallery),
            icon: const Icon(Icons.widgets_outlined),
            selectedIcon: const Icon(Icons.widgets_rounded),
          ),
          SizedBox(width: wide ? Gaps.lg : Gaps.sm),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _gallery ? null : _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  minWidth: 88,
                  groupAlignment: -0.9,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.forum_outlined),
                      selectedIcon: Icon(Icons.forum_rounded),
                      label: Text('Chat'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.search_rounded),
                      selectedIcon: Icon(Icons.manage_search_rounded),
                      label: Text('Search'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
      // The gallery is not a tab, so phones hide the tab bar while it shows.
      bottomNavigationBar: wide || _gallery
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              height: 68,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.forum_outlined),
                  selectedIcon: Icon(Icons.forum_rounded),
                  label: 'Chat',
                ),
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_rounded),
                  selectedIcon: Icon(Icons.manage_search_rounded),
                  label: 'Search',
                ),
              ],
            ),
    );
  }
}

/// App bar button that shows or hides the A2UI stream inspector.
class _InspectorToggle extends StatelessWidget {
  const _InspectorToggle({
    required this.open,
    required this.compact,
    required this.onPressed,
  });

  final bool open;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const String tip = 'Show the A2UI messages as they arrive';
    final Icon icon = Icon(
      open ? Icons.data_object_rounded : Icons.data_object_outlined,
    );
    if (compact) {
      return IconButton(
        tooltip: tip,
        isSelected: open,
        onPressed: onPressed,
        icon: icon,
      );
    }
    final Widget label = Text(open ? 'Hide stream' : 'Show stream');
    return Tooltip(
      message: tip,
      child: open
          ? FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: icon,
              label: label,
            )
          : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: label),
    );
  }
}
