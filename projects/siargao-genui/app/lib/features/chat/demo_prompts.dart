import 'package:flutter/foundation.dart';

/// A demo prompt chip. The prompt text matches `fixtures/<intent>.json`
/// (checked by a test).
@immutable
class DemoPrompt {
  /// Creates a [DemoPrompt].
  const DemoPrompt({
    required this.intent,
    required this.label,
    required this.prompt,
  });

  /// Intent id sent as `metadata.siargao.intent`.
  final String intent;

  /// Short chip label.
  final String label;

  /// Full prompt text.
  final String prompt;
}

/// The four chat intents, in demo order.
const List<DemoPrompt> demoPrompts = [
  DemoPrompt(
    intent: 'first_time_trip',
    label: 'First trip, 4 days',
    prompt: 'Plan my first trip to Siargao, 4 days, mid budget',
  ),
  DemoPrompt(
    intent: 'returning_flexible',
    label: 'Been before, flexible dates',
    prompt:
        "I've been to Siargao before. My dates are flexible. "
        'Where should I go this time?',
  ),
  DemoPrompt(
    intent: 'flights_under_8000',
    label: 'Flights under 8,000',
    prompt: 'Flights to Siargao under 8,000',
  ),
  DemoPrompt(
    intent: 'surf_this_week',
    label: 'Surf this week',
    prompt: "How's the surf in Siargao this week?",
  ),
];

/// The demo prompt for [intent], or null.
DemoPrompt? demoPromptFor(String? intent) {
  for (final DemoPrompt p in demoPrompts) {
    if (p.intent == intent) return p;
  }
  return null;
}
