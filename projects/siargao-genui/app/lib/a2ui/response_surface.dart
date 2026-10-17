import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../inspector/wire_log.dart';
import '../theme/app_theme.dart';
import 'a2ui_surface_view.dart';
import 'surface_session.dart';

/// Renders a list of A2UI messages as one surface. Owns its
/// [SurfaceSession] and rebuilds it when [messages] change identity.
///
/// With the inspector open and the pace set to Slow or Step, it applies the
/// messages one at a time so you can watch the surface build up, and it
/// registers a replay callback on [trace].
class ResponseSurface extends StatefulWidget {
  /// Creates a [ResponseSurface].
  const ResponseSurface({
    super.key,
    required this.messages,
    this.entries = const [],
    this.trace,
    this.onAction,
  });

  /// Decoded A2UI messages.
  final List<Map<String, Object?>> messages;

  /// Inspector entries for [messages], same order, or empty.
  final List<WireEntry> entries;

  /// Inspector trace that delivered [messages], if any.
  final WireTrace? trace;

  /// Button actions from the surface.
  final void Function(SurfaceAction action)? onAction;

  @override
  State<ResponseSurface> createState() => _ResponseSurfaceState();
}

class _ResponseSurfaceState extends State<ResponseSurface> {
  SurfaceSession? _session;
  int _applied = 0;
  int _run = 0;
  bool _paced = false;

  WireLog? get _wire => context.getInheritedWidgetOfExactType<AppScope>()?.wire;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(ResponseSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.messages, widget.messages)) {
      _detach(oldWidget.trace);
      _start();
    }
  }

  @override
  void dispose() {
    _run++;
    _detach(widget.trace);
    _session?.dispose();
    super.dispose();
  }

  void _detach(WireTrace? trace) {
    if (trace != null && trace.replay == _replay) trace.replay = null;
  }

  void _replay() {
    if (!mounted) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    setState(() => _start(replay: true));
  }

  WireEntry? _entry(int i) =>
      i < widget.entries.length ? widget.entries[i] : null;

  void _start({bool replay = false}) {
    final int run = ++_run;
    _session?.dispose();
    _session = SurfaceSession();
    _applied = 0;
    widget.trace?.replay = _replay;
    final WireLog? wire = _wire;
    if (wire != null) {
      for (final WireEntry e in widget.entries) {
        wire.markRendered(e, rendered: false);
      }
    }
    RenderPace pace = wire?.effectivePace ?? RenderPace.instant;
    // A replay at instant pace would look like nothing happened.
    if (replay && pace == RenderPace.instant) pace = RenderPace.slow;
    _paced = pace != RenderPace.instant;
    if (!_paced) {
      while (_applied < widget.messages.length) {
        _applyNext(wire);
      }
      return;
    }
    unawaited(_pump(run, wire, firstPace: pace));
  }

  void _applyNext(WireLog? wire) {
    if (_applied >= widget.messages.length) return;
    _session!.apply([widget.messages[_applied]]);
    final WireEntry? e = _entry(_applied);
    if (e != null) wire?.markRendered(e);
    _applied++;
  }

  Future<void> _pump(
    int run,
    WireLog? wire, {
    required RenderPace firstPace,
  }) async {
    RenderPace pace = firstPace;
    while (_applied < widget.messages.length) {
      if (pace == RenderPace.slow) {
        await Future<void>.delayed(WireLog.slowDelay);
      } else if (pace == RenderPace.step && wire != null) {
        await wire.waitForStep();
      }
      if (!mounted || run != _run) return;
      setState(() => _applyNext(wire));
      // Follow pace changes made while this surface is building, but keep a
      // replay going at Slow if the user has Instant selected.
      final RenderPace now = wire?.effectivePace ?? RenderPace.instant;
      pace = now == RenderPace.instant && firstPace == RenderPace.slow
          ? RenderPace.slow
          : now;
      if (pace == RenderPace.instant) {
        setState(() {
          while (_applied < widget.messages.length) {
            _applyNext(wire);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final SurfaceSession session = _session!;
    final int total = widget.messages.length;
    final bool building = _paced && _applied < total;
    final bool hasComponents = widget.messages
        .take(_applied)
        .any((m) => m.containsKey('updateComponents'));
    final Widget surface = hasComponents
        ? A2uiSurfaceView(session: session, onAction: widget.onAction)
        : _WaitingBox(created: session.context != null);
    if (!_paced) return surface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BuildStrip(
          applied: _applied,
          total: total,
          next: building ? a2uiTypeOf(widget.messages[_applied]) : null,
        ),
        const SizedBox(height: Gaps.md),
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(Gaps.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card + Gaps.sm),
            border: Border.all(
              color: building ? AppColors.teal : Colors.transparent,
              width: 2,
            ),
          ),
          child: surface,
        ),
      ],
    );
  }
}

/// "Rendering 2 of 3, next: updateDataModel" above a paced surface.
class _BuildStrip extends StatelessWidget {
  const _BuildStrip({
    required this.applied,
    required this.total,
    required this.next,
  });

  final int applied;
  final int total;
  final String? next;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool done = next == null;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gaps.lg,
        vertical: Gaps.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.downloading_rounded,
                size: 20,
                color: AppColors.tealInk,
              ),
              const SizedBox(width: Gaps.sm),
              Expanded(
                child: Text(
                  done
                      ? 'Applied all $total A2UI messages'
                      : 'Applied $applied of $total A2UI messages. '
                            'Next: $next',
                  style: t.labelLarge?.copyWith(color: AppColors.tealInk),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gaps.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 1 : applied / total,
              minHeight: 6,
              color: AppColors.teal,
              backgroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stands in for the surface until `updateComponents` is applied.
class _WaitingBox extends StatelessWidget {
  const _WaitingBox({required this.created});

  final bool created;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      height: 160,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(Gaps.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: AppColors.line, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            created ? Icons.crop_square_rounded : Icons.hourglass_empty_rounded,
            color: AppColors.inkMuted,
          ),
          const SizedBox(height: Gaps.sm),
          Text(
            created
                ? 'Surface created. No components yet.'
                : 'Waiting for createSurface',
            style: t.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Gaps.xs),
          Text(
            created
                ? 'updateComponents describes the widget tree.'
                : 'createSurface opens a surface with a catalog.',
            style: t.bodyMedium?.copyWith(color: AppColors.inkMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
