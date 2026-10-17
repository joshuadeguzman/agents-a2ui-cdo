import 'package:flutter/material.dart';

import '../../a2ui/a2ui_surface_view.dart';
import '../../a2ui/response_surface.dart';
import '../../app_scope.dart';
import '../../services/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/badges.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/status_panels.dart';
import 'chat_controller.dart';
import 'demo_prompts.dart';
import 'plain_text_view.dart';

/// Which answer the chat shows.
enum ChatView {
  /// Markdown only.
  text,

  /// A2UI only.
  a2ui,

  /// Side by side (wide screens).
  both;

  /// Parses `view=` from a deep link.
  static ChatView? parse(String? value) => switch (value) {
    'text' => ChatView.text,
    'a2ui' => ChatView.a2ui,
    'both' => ChatView.both,
    _ => null,
  };
}

/// Width at which plain text and A2UI show side by side.
const double sideBySideBreakpoint = 1100;

/// The Chat tab: demo prompt chips, a text field, and a toggle between the
/// plain text answer and the A2UI answer to the same prompt.
class ChatScreen extends StatefulWidget {
  /// Creates a [ChatScreen].
  const ChatScreen({super.key, this.initialIntent, this.initialView});

  /// Demo intent to run on open (deep link `intent=`).
  final String? initialIntent;

  /// Initial view (deep link `view=`).
  final ChatView? initialView;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatController? _chat;
  final TextEditingController _input = TextEditingController();
  final Map<String, GlobalKey> _turnKeys = {};
  final Map<ChatView, ScrollController> _scrolls = {
    for (final ChatView v in ChatView.values) v: ScrollController(),
  };
  ChatView? _view;
  int _seenTurns = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_chat == null) {
      _chat = ChatController(AppScope.of(context).backend)
        ..addListener(_onChat);
      final DemoPrompt? p = demoPromptFor(widget.initialIntent);
      if (p != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _chat!.send(p.prompt, intent: p.intent);
        });
      }
    }
  }

  @override
  void dispose() {
    _chat?.removeListener(_onChat);
    _chat?.dispose();
    _input.dispose();
    for (final ScrollController c in _scrolls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChat() {
    if (!mounted) return;
    setState(() {});
    final int count = _chat!.turns.length;
    if (count > _seenTurns) {
      _seenTurns = count;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealLatest());
    }
  }

  /// Scrolls every visible column so the newest prompt sits at the top.
  void _revealLatest() {
    final ChatTurn? latest = _chat?.latest;
    // The first answer already starts at the top of the page.
    if (latest == null || !mounted || _chat!.turns.length < 2) return;
    for (final MapEntry<String, GlobalKey> e in _turnKeys.entries) {
      if (!e.key.startsWith('${latest.id}:')) continue;
      final BuildContext? ctx = e.value.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
  }

  GlobalKey _keyFor(ChatTurn turn, ResponseFormat format) =>
      _turnKeys.putIfAbsent('${turn.id}:${format.name}', GlobalKey.new);

  void _send(String prompt, {String? intent}) {
    if (prompt.trim().isEmpty) return;
    _input.clear();
    _chat!.send(prompt, intent: intent);
  }

  Future<void> _onAction(SurfaceAction action) async {
    final SurfaceResponse? reply = await handleSurfaceAction(context, action);
    if (reply != null && reply.hasSurface && mounted) {
      _chat!.addAgentSurface('Action: ${action.name}', reply);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use the width this screen gets, not the window: the inspector panel
    // can take part of it.
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= sideBySideBreakpoint;
        final ChatView requested =
            _view ??
            widget.initialView ??
            (wide ? ChatView.both : ChatView.a2ui);
        final ChatView view = (!wide && requested == ChatView.both)
            ? ChatView.a2ui
            : requested;
        final ChatTurn? latest = _chat!.latest;
        final Slot? headerSlot = latest == null
            ? null
            : (view == ChatView.text ? latest.text : latest.a2ui);
        final EdgeInsets pad = pagePadding(constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: pad.copyWith(top: Gaps.lg, bottom: Gaps.md),
              child: ScreenHeader(
                title: 'Chat',
                subtitle: 'One prompt, two answers: plain text and A2UI.',
                badges: [
                  const PathPill(path: DeliveryPath.a2a),
                  if (latest != null)
                    ModelCallsPill(meta: headerSlot?.response?.meta),
                ],
                trailing: _ViewToggle(
                  value: view,
                  allowBoth: wide,
                  onChanged: (v) => setState(() => _view = v),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: view == ChatView.both
                  ? _sideBySide(pad)
                  : _conversation(
                      view == ChatView.text
                          ? ResponseFormat.text
                          : ResponseFormat.a2ui,
                      _scrolls[view]!,
                      pad,
                      maxWidth: view == ChatView.text ? 920 : 1180,
                    ),
            ),
            _Composer(
              controller: _input,
              compact: latest != null || constraints.maxWidth < 640,
              onSend: _send,
            ),
          ],
        );
      },
    );
  }

  Widget _sideBySide(EdgeInsets pad) {
    Widget column(String title, IconData icon, ResponseFormat format) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.white,
              padding: pad.copyWith(top: Gaps.md, bottom: Gaps.md),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: AppColors.teal),
                  const SizedBox(width: Gaps.sm),
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _conversation(
                format,
                _scrolls[format == ResponseFormat.text
                    ? ChatView.text
                    : ChatView.a2ui]!,
                pad,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        column('Plain text', Icons.notes_rounded, ResponseFormat.text),
        const VerticalDivider(width: 1),
        column('A2UI', Icons.dashboard_customize_outlined, ResponseFormat.a2ui),
      ],
    );
  }

  Widget _conversation(
    ResponseFormat format,
    ScrollController scroll,
    EdgeInsets pad, {
    double maxWidth = double.infinity,
  }) {
    final List<ChatTurn> turns = _chat!.turns;
    if (turns.isEmpty) return const _EmptyState();
    return SingleChildScrollView(
      controller: scroll,
      padding: pad.copyWith(top: Gaps.lg, bottom: Gaps.xxl),
      child: ContentWidth(
        maxWidth: maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final ChatTurn turn in turns)
              Padding(
                key: _keyFor(turn, format),
                padding: EdgeInsets.only(
                  top: turn == turns.first ? 0 : Gaps.lg,
                  bottom: Gaps.xl,
                ),
                child: _TurnView(
                  turn: turn,
                  format: format,
                  onAction: _onAction,
                  onRetry: () => _send(turn.prompt, intent: turn.intent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.value,
    required this.allowBoth,
    required this.onChanged,
  });

  final ChatView value;
  final bool allowBoth;
  final ValueChanged<ChatView> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ChatView>(
      showSelectedIcon: false,
      segments: [
        const ButtonSegment(
          value: ChatView.text,
          label: Text('Text'),
          icon: Icon(Icons.notes_rounded),
        ),
        const ButtonSegment(
          value: ChatView.a2ui,
          label: Text('A2UI'),
          icon: Icon(Icons.dashboard_customize_outlined),
        ),
        if (allowBoth)
          const ButtonSegment(
            value: ChatView.both,
            label: Text('Both'),
            icon: Icon(Icons.view_column_outlined),
          ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({
    required this.turn,
    required this.format,
    required this.onAction,
    required this.onRetry,
  });

  final ChatTurn turn;
  final ResponseFormat format;
  final void Function(SurfaceAction action) onAction;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final Slot slot = format == ResponseFormat.text ? turn.text : turn.a2ui;
    final SurfaceResponse? r = slot.response;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PromptBubble(text: turn.prompt),
        const SizedBox(height: Gaps.lg),
        if (slot.loading)
          LoadingPanel(
            label: AppScope.of(context).backend.isLive
                ? 'Asking the agent'
                : 'Loading the recorded answer',
          )
        else if (slot.error != null)
          ErrorPanel(message: slot.error!, onRetry: onRetry)
        else if (r != null) ...[
          _AnswerCaption(response: r),
          const SizedBox(height: Gaps.md),
          if (format == ResponseFormat.a2ui && r.hasSurface)
            ResponseSurface(
              messages: r.messages,
              entries: r.entries,
              trace: r.trace,
              onAction: onAction,
            )
          else
            PlainTextView(markdown: r.text ?? 'No text answer.'),
        ],
      ],
    );
  }
}

class _AnswerCaption extends StatelessWidget {
  const _AnswerCaption({required this.response});

  final SurfaceResponse response;

  @override
  Widget build(BuildContext context) {
    final String meta = response.meta?.label ?? 'Model calls unknown';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${response.path.label} answer · $meta',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: AppColors.inkMuted),
        ),
        if (response.note != null) ...[
          const SizedBox(height: Gaps.xs),
          NoteLine(text: response.note!),
        ],
      ],
    );
  }
}

class _PromptBubble extends StatelessWidget {
  const _PromptBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.teal,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Gaps.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.tealSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.surfing_rounded,
                  size: 36,
                  color: AppColors.tealInk,
                ),
              ),
              const SizedBox(height: Gaps.xl),
              Text(
                'Plan a Siargao trip',
                style: t.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gaps.md),
              Text(
                'Pick a prompt below. Each one asks the agent twice: once for '
                'plain text and once for A2UI, so you can compare them.',
                style: t.bodyLarge?.copyWith(color: AppColors.inkMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.compact,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool compact;
  final void Function(String prompt, {String? intent}) onSend;

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = [
      for (final DemoPrompt p in demoPrompts)
        ActionChip(
          avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: Text(p.label),
          tooltip: p.prompt,
          onPressed: () => onSend(p.prompt, intent: p.intent),
        ),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final EdgeInsets pad = pagePadding(constraints.maxWidth);
          return Padding(
            padding: pad.copyWith(top: Gaps.md, bottom: Gaps.md),
            child: ContentWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (compact)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(spacing: Gaps.sm, children: chips),
                    )
                  else
                    Wrap(
                      spacing: Gaps.sm,
                      runSpacing: Gaps.sm,
                      children: chips,
                    ),
                  const SizedBox(height: Gaps.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          textInputAction: TextInputAction.send,
                          onSubmitted: onSend,
                          decoration: const InputDecoration(
                            hintText: 'Ask about a Siargao trip',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: Gaps.sm),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: () => onSend(controller.text),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
