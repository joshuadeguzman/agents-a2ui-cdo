import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../a2ui/response_surface.dart';
import '../../app_scope.dart';
import '../../services/demo_backend.dart';
import '../../services/models.dart';
import '../../services/offline_stays.dart';
import '../../theme/app_theme.dart';
import '../../widgets/badges.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/status_panels.dart';

/// Areas in the sample stays dataset.
const List<String> searchAreas = [
  'Cloud 9',
  'General Luna',
  'Pacifico',
  'Pilar',
  'Burgos',
];

/// The Search tab: a small form that calls the MCP tool `search_stays` and
/// renders the `stays_near_cloud9` template surface it returns.
class SearchScreen extends StatefulWidget {
  /// Creates a [SearchScreen].
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _area = StayQuery.fixtureDefault.area;
  int _nights = StayQuery.fixtureDefault.nights;
  final TextEditingController _price = TextEditingController(
    text: '${StayQuery.fixtureDefault.maxPrice}',
  );
  Future<SurfaceResponse>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _run();
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  StayQuery get _query => StayQuery(
    area: _area,
    nights: _nights,
    maxPrice: int.tryParse(_price.text.replaceAll(',', '').trim()) ?? 4500,
  );

  Future<SurfaceResponse> _run() =>
      AppScope.of(context).backend.searchStays(_query);

  void _search() => setState(() => _future = _run());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SurfaceResponse>(
      future: _future,
      builder: (context, snapshot) {
        final SurfaceResponse? r =
            snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null;
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
                      title: 'Search stays',
                      subtitle:
                          'A template surface returned by the MCP tool '
                          '$searchToolName.',
                      badges: [
                        const PathPill(path: DeliveryPath.mcpTool),
                        if (r != null) ModelCallsPill(meta: r.meta),
                      ],
                    ),
                    const SizedBox(height: Gaps.lg),
                    _form(constraints.maxWidth < 760),
                    const SizedBox(height: Gaps.xl),
                    if (snapshot.hasError &&
                        snapshot.connectionState == ConnectionState.done)
                      ErrorPanel(
                        message: friendlyError(snapshot.error!),
                        onRetry: _search,
                      )
                    else if (r == null)
                      const LoadingPanel(label: 'Searching stays')
                    else ...[
                      if (r.note != null) ...[
                        NoteLine(text: r.note!),
                        const SizedBox(height: Gaps.md),
                      ],
                      ResponseSurface(
                        messages: r.messages,
                        entries: r.entries,
                        trace: r.trace,
                        onAction: (a) => handleSurfaceAction(context, a),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _form(bool narrow) {
    final Widget area = DropdownButtonFormField<String>(
      initialValue: _area,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Area'),
      items: [
        for (final String a in searchAreas)
          DropdownMenuItem(value: a, child: Text(a)),
      ],
      onChanged: (v) => setState(() => _area = v ?? _area),
    );
    final Widget nights = DropdownButtonFormField<int>(
      initialValue: _nights,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Nights'),
      items: [
        for (var n = 1; n <= 14; n++)
          DropdownMenuItem(value: n, child: Text('$n')),
      ],
      onChanged: (v) => setState(() => _nights = v ?? _nights),
    );
    final Widget price = TextField(
      controller: _price,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(
        labelText: 'Max price per night',
        prefixText: 'PHP ',
      ),
      onSubmitted: (_) => _search(),
    );
    final Widget button = FilledButton.icon(
      onPressed: _search,
      icon: const Icon(Icons.search_rounded),
      label: const Text('Search'),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.lg),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  area,
                  const SizedBox(height: Gaps.md),
                  Row(
                    children: [
                      Expanded(flex: 2, child: nights),
                      const SizedBox(width: Gaps.md),
                      Expanded(flex: 3, child: price),
                    ],
                  ),
                  const SizedBox(height: Gaps.md),
                  button,
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 4, child: area),
                  const SizedBox(width: Gaps.md),
                  Expanded(flex: 2, child: nights),
                  const SizedBox(width: Gaps.md),
                  Expanded(flex: 4, child: price),
                  const SizedBox(width: Gaps.md),
                  button,
                ],
              ),
      ),
    );
  }
}
