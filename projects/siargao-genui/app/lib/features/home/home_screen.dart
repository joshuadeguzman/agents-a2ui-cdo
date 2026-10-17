import 'package:flutter/material.dart';

import '../../a2ui/response_surface.dart';
import '../../app_scope.dart';
import '../../services/demo_backend.dart';
import '../../services/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/badges.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/status_panels.dart';

/// The Home tab: the `home_first_run` surface from the MCP resource
/// `a2ui://home/first-run`.
class HomeScreen extends StatefulWidget {
  /// Creates a [HomeScreen].
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<SurfaceResponse>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).backend.home();
  }

  void _reload() {
    setState(() => _future = AppScope.of(context).backend.home());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SurfaceResponse>(
      future: _future,
      builder: (context, snapshot) {
        final SurfaceResponse? r = snapshot.data;
        return LayoutBuilder(
          builder: (context, constraints) {
            final EdgeInsets pad = pagePadding(constraints.maxWidth);
            return SingleChildScrollView(
              padding: pad.copyWith(top: Gaps.lg, bottom: Gaps.xxl),
              child: ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ScreenHeader(
                      title: 'Home',
                      subtitle:
                          'A fixed surface served as an MCP resource: '
                          '$homeResourceUri',
                      badges: [
                        const PathPill(path: DeliveryPath.mcpResource),
                        if (r != null) ModelCallsPill(meta: r.meta),
                      ],
                      trailing: IconButton(
                        tooltip: 'Reload',
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ),
                    const SizedBox(height: Gaps.xl),
                    if (snapshot.hasError)
                      ErrorPanel(
                        message: friendlyError(snapshot.error!),
                        onRetry: _reload,
                      )
                    else if (r == null)
                      const LoadingPanel(label: 'Loading the home surface')
                    else
                      ResponseSurface(
                        messages: r.messages,
                        entries: r.entries,
                        trace: r.trace,
                        onAction: (a) => handleSurfaceAction(context, a),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
