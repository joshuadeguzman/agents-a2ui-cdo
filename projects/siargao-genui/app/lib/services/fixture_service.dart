import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// A recorded surface from `fixtures/<intent>.json` (docs/CONTRACT.md).
@immutable
class Fixture {
  /// Creates a [Fixture].
  const Fixture({
    required this.intent,
    required this.title,
    required this.prompt,
    required this.path,
    required this.source,
    required this.modelCalls,
    required this.text,
    required this.messages,
  });

  /// Reads a fixture file.
  factory Fixture.fromJson(Map<String, Object?> json) => Fixture(
    intent: json['intent'] as String,
    title: json['title'] as String,
    prompt: json['prompt'] as String,
    path: DeliveryPath.parse(json['path']),
    source: json['source'] as String,
    modelCalls: (json['modelCalls'] as num).toInt(),
    text: json['text'] as String,
    messages: [
      for (final Object? m in json['messages'] as List<Object?>)
        (m as Map).cast<String, Object?>(),
    ],
  );

  /// Intent id, also the surface id.
  final String intent;

  /// Human title.
  final String title;

  /// Demo prompt.
  final String prompt;

  /// Delivery path.
  final DeliveryPath path;

  /// `template` or `model`.
  final String source;

  /// Model calls that produced it.
  final int modelCalls;

  /// Markdown answer for the plain text side.
  final String text;

  /// A2UI messages.
  final List<Map<String, Object?>> messages;

  /// Metadata equivalent to what the servers send.
  ResponseMeta get meta =>
      ResponseMeta(intent: intent, source: source, modelCalls: modelCalls);
}

/// One sample stay from `fixtures/stays_dataset.json`.
@immutable
class Stay {
  /// Creates a [Stay].
  const Stay({
    required this.id,
    required this.name,
    required this.area,
    required this.pricePerNight,
    required this.rating,
    required this.note,
    required this.image,
  });

  /// Reads a stay.
  factory Stay.fromJson(Map<String, Object?> json) => Stay(
    id: json['id'] as String,
    name: json['name'] as String,
    area: json['area'] as String,
    pricePerNight: json['pricePerNight'] as num,
    rating: json['rating'] as num,
    note: json['note'] as String,
    image: json['image'] as String,
  );

  /// Stable id.
  final String id;

  /// Display name.
  final String name;

  /// Area, for example `Cloud 9`.
  final String area;

  /// Sample price per night in PHP.
  final num pricePerNight;

  /// Guest rating.
  final num rating;

  /// One line note.
  final String note;

  /// Image key.
  final String image;

  /// JSON for the data model.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'area': area,
    'pricePerNight': pricePerNight,
    'rating': rating,
    'note': note,
    'image': image,
  };
}

/// Loads fixtures bundled under `assets/fixtures/` (offline mode).
class FixtureService {
  /// Creates a [FixtureService] reading from [bundle] (default root bundle).
  FixtureService({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final Map<String, Future<Fixture>> _cache = {};
  Future<List<Stay>>? _stays;

  /// Every intent with a fixture.
  static const List<String> intents = [
    'first_time_trip',
    'returning_flexible',
    'flights_under_8000',
    'surf_this_week',
    'home_first_run',
    'stays_near_cloud9',
  ];

  /// Loads `assets/fixtures/<intent>.json`.
  Future<Fixture> load(String intent) {
    if (!intents.contains(intent)) {
      return Future.error(ArgumentError.value(intent, 'intent', 'no fixture'));
    }
    return _cache.putIfAbsent(intent, () async {
      final String raw = await _bundle.loadString(
        'assets/fixtures/$intent.json',
      );
      return Fixture.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    });
  }

  /// Loads the sample stays behind the `search_stays` tool.
  Future<List<Stay>> stays() => _stays ??= () async {
    final String raw = await _bundle.loadString(
      'assets/fixtures/stays_dataset.json',
    );
    final Map<String, Object?> json = (jsonDecode(raw) as Map)
        .cast<String, Object?>();
    return [
      for (final Object? s in json['stays'] as List<Object?>)
        Stay.fromJson((s as Map).cast<String, Object?>()),
    ];
  }();
}
