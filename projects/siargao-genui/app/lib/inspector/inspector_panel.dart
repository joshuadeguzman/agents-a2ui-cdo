import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme/app_theme.dart';
import 'json_view.dart';
import 'wire_log.dart';

/// The A2UI stream inspector: every request the app sends and every message
/// it receives, in order, next to the surface they build.
class InspectorPanel extends StatefulWidget {
  /// Creates an [InspectorPanel].
  const InspectorPanel({super.key, this.onClose});

  /// Closes the panel.
  final VoidCallback? onClose;

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  final ScrollController _scroll = ScrollController();
  final Set<int> _expanded = {};
  WireLog? _wire;
  bool _pinned = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final WireLog wire = AppScope.of(context).wire;
    if (!identical(wire, _wire)) {
      _wire?.removeListener(_onLog);
      _wire = wire..addListener(_onLog);
    }
  }

  @override
  void dispose() {
    _wire?.removeListener(_onLog);
    _scroll.dispose();
    super.dispose();
  }

  void _onLog() {
    if (!mounted) return;
    setState(() {});
    if (_pinned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n is UserScrollNotification) {
      _pinned = n.metrics.extentAfter < 48;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final WireLog wire = _wire!;
    final List<WireTrace> traces = [
      for (final WireTrace t in wire.traces)
        if (wire.showText || !t.textOnly) t,
    ];
    final WireEntry? next = _nextToRender(traces);
    final ThemeData base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.teal,
          brightness: Brightness.dark,
        ).copyWith(primary: WireColors.accent, surface: WireColors.card),
        textTheme: base.textTheme.apply(
          bodyColor: WireColors.text,
          displayColor: WireColors.text,
        ),
        iconTheme: const IconThemeData(color: WireColors.muted),
        dividerColor: WireColors.line,
      ),
      child: ColoredBox(
        color: WireColors.background,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                wire: wire,
                onClose: widget.onClose,
                compact: constraints.maxHeight < 520,
              ),
              const Divider(height: 1, color: WireColors.line),
              if (wire.pace == RenderPace.step)
                _StepBar(enabled: wire.canStep, next: next, onStep: wire.step),
              Expanded(
                child: traces.isEmpty
                    ? const _Empty()
                    : NotificationListener<ScrollNotification>(
                        onNotification: _onScroll,
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(
                            Gaps.md,
                            Gaps.md,
                            Gaps.md,
                            Gaps.xl,
                          ),
                          itemCount: traces.length,
                          itemBuilder: (context, i) => _TraceCard(
                            trace: traces[i],
                            next: next,
                            expanded: _expanded,
                            onToggle: (id) => setState(
                              () => _expanded.contains(id)
                                  ? _expanded.remove(id)
                                  : _expanded.add(id),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The first A2UI message a surface on screen has not applied yet.
  static WireEntry? _nextToRender(List<WireTrace> traces) {
    for (final WireTrace t in traces) {
      if (t.replay == null) continue;
      for (final WireEntry e in t.a2uiEntries) {
        if (!e.rendered) return e;
      }
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.wire,
    required this.onClose,
    required this.compact,
  });

  final WireLog wire;
  final VoidCallback? onClose;

  /// Short panel (phones): drop the note and the text filter.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gaps.lg,
        compact ? Gaps.xs : Gaps.md,
        Gaps.sm,
        compact ? Gaps.sm : Gaps.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.data_object_rounded, color: WireColors.accent),
              const SizedBox(width: Gaps.sm),
              Expanded(
                child: Text(
                  'A2UI stream',
                  style: t.titleLarge?.copyWith(color: WireColors.text),
                ),
              ),
              IconButton(
                tooltip: 'Clear',
                onPressed: wire.clear,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: 'Close the inspector',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: Gaps.sm),
          Wrap(
            spacing: Gaps.sm,
            runSpacing: Gaps.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<RenderPace>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: WireColors.card,
                  foregroundColor: WireColors.text,
                  selectedBackgroundColor: WireColors.accent,
                  selectedForegroundColor: WireColors.background,
                  side: const BorderSide(color: WireColors.line),
                ),
                segments: const [
                  ButtonSegment(
                    value: RenderPace.instant,
                    label: Text('Instant'),
                    icon: Icon(Icons.bolt_rounded),
                  ),
                  ButtonSegment(
                    value: RenderPace.slow,
                    label: Text('Slow'),
                    icon: Icon(Icons.slow_motion_video_rounded),
                  ),
                  ButtonSegment(
                    value: RenderPace.step,
                    label: Text('Step'),
                    icon: Icon(Icons.skip_next_rounded),
                  ),
                ],
                selected: {wire.pace},
                onSelectionChanged: (s) => wire.pace = s.first,
              ),
              if (!compact)
                FilterChip(
                  backgroundColor: WireColors.card,
                  selectedColor: WireColors.cardActive,
                  checkmarkColor: WireColors.accent,
                  side: const BorderSide(color: WireColors.line),
                  labelStyle: const TextStyle(color: WireColors.text),
                  label: const Text('Text requests'),
                  selected: wire.showText,
                  onSelected: (v) => wire.showText = v,
                  tooltip: 'Also list the plain text half of each chat prompt',
                ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: Gaps.sm),
            Text(
              'Times are real arrival times. Slow and Step only hold each '
              'message before the app renders it.',
              style: t.bodySmall?.copyWith(color: WireColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({
    required this.enabled,
    required this.next,
    required this.onStep,
  });

  final bool enabled;
  final WireEntry? next;
  final VoidCallback onStep;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      color: WireColors.card,
      padding: const EdgeInsets.all(Gaps.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              enabled && next != null
                  ? 'Next: ${next!.title}'
                  : 'Send a prompt or open a tab. Each message waits here.',
              style: t.bodyMedium?.copyWith(color: WireColors.text),
            ),
          ),
          const SizedBox(width: Gaps.sm),
          FilledButton.icon(
            onPressed: enabled ? onStep : null,
            style: FilledButton.styleFrom(
              backgroundColor: WireColors.accent,
              foregroundColor: WireColors.background,
              disabledBackgroundColor: WireColors.line,
              disabledForegroundColor: WireColors.muted,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('Render next'),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.xl),
        child: Text(
          'Nothing yet. Pick a prompt, or open Home or Search, and the '
          'requests and A2UI messages show up here as they arrive.',
          textAlign: TextAlign.center,
          style: t.bodyLarge?.copyWith(color: WireColors.muted),
        ),
      ),
    );
  }
}

class _TraceCard extends StatelessWidget {
  const _TraceCard({
    required this.trace,
    required this.next,
    required this.expanded,
    required this.onToggle,
  });

  final WireTrace trace;
  final WireEntry? next;
  final Set<int> expanded;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final int a2ui = trace.a2uiEntries.length;
    final int rendered = trace.a2uiEntries.where((e) => e.rendered).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WireColors.card,
          borderRadius: BorderRadius.circular(Radii.small),
          border: Border.all(color: WireColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, 0, Gaps.sm),
              child: Row(
                children: [
                  _ChannelTag(channel: trace.channel),
                  const SizedBox(width: Gaps.sm),
                  Expanded(
                    child: Text(
                      trace.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleSmall?.copyWith(color: WireColors.text),
                    ),
                  ),
                  if (a2ui > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: Gaps.sm),
                      child: Text(
                        '$rendered/$a2ui rendered',
                        style: t.labelSmall?.copyWith(color: WireColors.muted),
                      ),
                    ),
                  if (trace.replay != null)
                    IconButton(
                      tooltip: 'Replay this surface message by message',
                      onPressed: trace.replay,
                      icon: const Icon(Icons.replay_rounded),
                      color: WireColors.accent,
                    )
                  else
                    const SizedBox(width: Gaps.md),
                ],
              ),
            ),
            const Divider(height: 1, color: WireColors.line),
            for (final WireEntry e in trace.entries)
              _EntryRow(
                entry: e,
                isNext: identical(e, next),
                expanded: expanded.contains(e.id),
                onTap: e.json == null ? null : () => onToggle(e.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChannelTag extends StatelessWidget {
  const _ChannelTag({required this.channel});

  final WireChannel channel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WireColors.background,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: WireColors.accent.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          channel.label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: WireColors.accent, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.isNext,
    required this.expanded,
    required this.onTap,
  });

  final WireEntry entry;
  final bool isNext;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool out = entry.direction == WireDirection.outgoing;
    final bool a2ui = entry.kind == WireKind.a2ui;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      color: isNext ? WireColors.cardActive : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gaps.md,
            vertical: Gaps.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      out ? Icons.north_east_rounded : Icons.south_west_rounded,
                      size: 18,
                      color: out ? WireColors.outgoing : WireColors.accent,
                    ),
                  ),
                  const SizedBox(width: Gaps.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: TextStyle(
                            fontFamily: monoFontFamily,
                            fontSize: a2ui ? 15 : 14,
                            fontWeight: FontWeight.w500,
                            color: a2ui ? WireColors.text : WireColors.muted,
                          ),
                        ),
                        if (entry.summary != null && entry.summary!.isNotEmpty)
                          Text(
                            entry.summary!,
                            maxLines: expanded ? null : 2,
                            overflow: expanded ? null : TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(
                              color: WireColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gaps.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '+${entry.offsetMs} ms',
                        style: const TextStyle(
                          fontFamily: monoFontFamily,
                          fontSize: 12,
                          color: WireColors.muted,
                        ),
                      ),
                      if (entry.bytes > 0)
                        Text(
                          _size(entry.bytes),
                          style: const TextStyle(
                            fontFamily: monoFontFamily,
                            fontSize: 12,
                            color: WireColors.muted,
                          ),
                        ),
                    ],
                  ),
                  if (a2ui) ...[
                    const SizedBox(width: Gaps.sm),
                    Tooltip(
                      message: entry.rendered
                          ? 'Rendered'
                          : (isNext ? 'Next to render' : 'Not rendered'),
                      child: Icon(
                        entry.rendered
                            ? Icons.check_circle_rounded
                            : Icons.pending_outlined,
                        size: 18,
                        color: entry.rendered
                            ? WireColors.rendered
                            : (isNext ? WireColors.accent : WireColors.muted),
                      ),
                    ),
                  ],
                ],
              ),
              if (expanded && entry.json != null) ...[
                const SizedBox(height: Gaps.sm),
                Container(
                  constraints: const BoxConstraints(maxHeight: 360),
                  padding: const EdgeInsets.all(Gaps.sm),
                  decoration: BoxDecoration(
                    color: WireColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: JsonView(value: entry.json),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _size(int bytes) =>
      bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB';
}
