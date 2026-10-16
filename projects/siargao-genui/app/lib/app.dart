import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'config.dart';
import 'deep_link.dart';
import 'features/chat/chat_screen.dart';
import 'features/gallery/gallery_screen.dart';
import 'features/home/home_screen.dart';
import 'features/search/search_screen.dart';
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
  });

  /// Configuration from `--dart-define`.
  final AppConfig config;

  /// Deep link from the URL.
  final DeepLink link;

  /// Backend override for tests.
  final DemoBackend? backend;

  @override
  State<SiargaoApp> createState() => _SiargaoAppState();
}

class _SiargaoAppState extends State<SiargaoApp> {
  late final DemoBackend _backend =
      widget.backend ?? DemoBackend.forConfig(widget.config);

  @override
  Widget build(BuildContext context) {
    return AppScope(
      config: widget.config,
      backend: _backend,
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
    final AppScope scope = AppScope.of(context);
    final bool wide = MediaQuery.sizeOf(context).width >= railBreakpoint;
    final Widget tabs = IndexedStack(
      index: _index,
      children: [for (var i = 0; i < _tabs.length; i++) _tabBody(i)],
    );
    final Widget content = _gallery ? const GalleryScreen() : tabs;

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
            const Icon(Icons.waves_rounded, color: AppColors.teal, size: 28),
            const SizedBox(width: Gaps.sm),
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
      bottomNavigationBar: wide
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
