import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:siargao_genui/a2ui/a2ui_surface_view.dart';
import 'package:siargao_genui/a2ui/surface_session.dart';
import 'package:siargao_genui/catalog/budget_slider.dart';
import 'package:siargao_genui/catalog/catalog_schemas.g.dart';
import 'package:siargao_genui/catalog/chip_row.dart';
import 'package:siargao_genui/catalog/flex_grid.dart';
import 'package:siargao_genui/catalog/image_asset.dart';
import 'package:siargao_genui/catalog/local_note.dart';
import 'package:siargao_genui/catalog/siargao_catalog.dart';

import '../support/test_harness.dart';

Map<String, Object?> event(String name, Map<String, Object?> context) => {
  'event': {'name': name, 'context': context},
};

void main() {
  group('catalog', () {
    test('has one item per component in the generated schemas', () {
      expect(
        siargaoCatalogItems.map((i) => i.name).toList(),
        siargaoComponentSchemas.keys.toList(),
      );
      expect(siargaoCatalog.catalogId, siargaoCatalogId);
      expect(
        siargaoCatalogId,
        'https://siargao-genui.example/catalogs/v1/catalog.json',
      );
    });

    test('item schemas carry the generated required properties', () {
      for (final CatalogItem item in siargaoCatalogItems) {
        final Map<String, Object?> schema = item.dataSchema.value;
        final List<Object?> required = schema['required']! as List<Object?>;
        final List<Object?> generated =
            siargaoComponentSchemas[item.name]!['required']! as List<Object?>;
        expect(required, containsAll(generated), reason: item.name);
        expect(required, contains('component'), reason: item.name);
      }
    });
  });

  group('Stack', () {
    testWidgets('renders children in order with literal props', (t) async {
      await pumpSurface(
        t,
        surfaceMessages('s', [
          {
            'id': 'root',
            'component': 'Stack',
            'children': ['a', 'b'],
            'gap': 'large',
          },
          {'id': 'a', 'component': 'Heading', 'title': 'First'},
          {'id': 'b', 'component': 'Heading', 'title': 'Second'},
        ]),
      );
      final Offset a = t.getTopLeft(find.text('First'));
      final Offset b = t.getTopLeft(find.text('Second'));
      expect(a.dy, lessThan(b.dy));
    });

    testWidgets('renders template children bound to a list', (t) async {
      await pumpSurface(
        t,
        surfaceMessages(
          's',
          [
            {
              'id': 'root',
              'component': 'Stack',
              'children': {'path': '/spots', 'componentId': 'spot'},
            },
            {
              'id': 'spot',
              'component': 'Heading',
              'title': {'path': 'name'},
            },
          ],
          {
            'spots': [
              {'name': 'Guyam'},
              {'name': 'Daku'},
            ],
          },
        ),
      );
      expect(find.text('Guyam'), findsOneWidget);
      expect(find.text('Daku'), findsOneWidget);
    });
  });

  group('Heading', () {
    testWidgets('renders literal props and a 16:9 image placeholder', (
      t,
    ) async {
      await pumpSurface(
        t,
        single({
          'component': 'Heading',
          'eyebrow': 'Surf report',
          'title': 'Waves this week',
          'subtitle': 'Small and clean in the mornings.',
          'image': 'cloud-9-boardwalk',
        }),
      );
      expect(find.text('SURF REPORT'), findsOneWidget);
      // The last two words are glued so the heading never ends in a widow.
      expect(find.text('Waves this\u00A0week'), findsOneWidget);
      expect(find.textContaining('Waves'), findsOneWidget);
      expect(find.textContaining('Small and clean'), findsOneWidget);
      final AspectRatio ratio = t.widget(find.byType(AspectRatio));
      expect(ratio.aspectRatio, closeTo(16 / 9, 0.001));
      expect(find.byType(ImagePlaceholder), findsOneWidget);
    });

    testWidgets('renders bound props from the data model', (t) async {
      await pumpSurface(
        t,
        single(
          {
            'component': 'Heading',
            'title': {'path': '/hero/title'},
            'subtitle': {'path': '/hero/subtitle'},
          },
          {
            'hero': {'title': 'Plan your trip', 'subtitle': 'Bound subtitle'},
          },
        ),
      );
      expect(find.textContaining('Plan your'), findsOneWidget);
      expect(find.textContaining('Bound'), findsOneWidget);
    });

    testWidgets('renders as a tile with a 3:2 image inside a FlexGrid', (
      t,
    ) async {
      await pumpSurface(
        t,
        surfaceMessages('s', [
          {
            'id': 'root',
            'component': 'Stack',
            'children': ['g'],
          },
          {
            'id': 'g',
            'component': 'FlexGrid',
            'children': ['h'],
          },
          {
            'id': 'h',
            'component': 'Heading',
            'title': 'Sugba Lagoon',
            'image': 'sugba-lagoon',
          },
        ]),
      );
      expect(find.byType(Card), findsOneWidget);
      final AspectRatio ratio = t.widget(find.byType(AspectRatio));
      expect(ratio.aspectRatio, closeTo(3 / 2, 0.001));
    });
  });

  group('ItineraryDay', () {
    testWidgets('renders literal items', (t) async {
      await pumpSurface(
        t,
        single({
          'component': 'ItineraryDay',
          'day': 2,
          'title': 'Surf lesson',
          'items': [
            {'time': '07:00', 'activity': 'Lesson', 'note': 'Bring water'},
            {'time': '12:00', 'activity': 'Lunch'},
          ],
        }),
      );
      expect(find.text('Day 2'), findsOneWidget);
      expect(find.text('07:00'), findsOneWidget);
      expect(find.text('Lesson'), findsOneWidget);
      expect(find.text('Bring water'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
    });

    testWidgets('renders bound items from the data model', (t) async {
      await pumpSurface(
        t,
        single(
          {
            'component': 'ItineraryDay',
            'day': {'path': '/d/day'},
            'title': {'path': '/d/title'},
            'items': {'path': '/d/items'},
            'image': {'path': '/d/image'},
          },
          {
            'd': {
              'day': 3,
              'title': 'Islands',
              'image': 'guyam-island',
              'items': [
                {'time': '08:00', 'activity': 'Boat out'},
              ],
            },
          },
        ),
      );
      expect(find.text('Day 3'), findsOneWidget);
      expect(find.text('Boat out'), findsOneWidget);
      expect(find.byType(ImagePlaceholder), findsOneWidget);
    });
  });

  group('CostBreakdown', () {
    testWidgets('renders literal lines and computes the total', (t) async {
      await pumpSurface(
        t,
        single({
          'component': 'CostBreakdown',
          'title': 'Budget',
          'items': [
            {'label': 'Flight', 'amount': 7500},
            {'label': 'Stay', 'amount': 4500},
          ],
        }),
      );
      expect(find.text('PHP 7,500'), findsOneWidget);
      expect(find.text('PHP 4,500'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('PHP 12,000'), findsOneWidget);
    });

    testWidgets('renders bound lines, currency and total label', (t) async {
      await pumpSurface(
        t,
        single(
          {
            'component': 'CostBreakdown',
            'title': {'path': '/b/title'},
            'currency': {'path': '/b/currency'},
            'items': {'path': '/b/items'},
            'totalLabel': {'path': '/b/total'},
          },
          {
            'b': {
              'title': 'Fare',
              'currency': 'USD',
              'total': 'All in',
              'items': [
                {'label': 'Base', 'amount': 100},
                {'label': 'Tax', 'amount': 20.5},
              ],
            },
          },
        ),
      );
      expect(find.text('All in'), findsOneWidget);
      expect(find.text('USD 120.50'), findsOneWidget);
    });
  });

  group('StayCard', () {
    testWidgets('renders literal props and dispatches Choose', (t) async {
      final List<SurfaceAction> actions = [];
      await pumpSurface(
        t,
        single({
          'component': 'StayCard',
          'image': 'stay-palm-villa',
          'name': 'Palm Villa',
          'note': 'Private pool',
          'pricePerNight': 7800,
          'area': 'Cloud 9',
          'rating': 4.8,
          'action': event('choose_stay', {'stayId': 'palm-villa', 'nights': 3}),
        }),
        actions: actions,
      );
      expect(find.textContaining('Palm'), findsOneWidget);
      expect(find.text('PHP 7,800'), findsOneWidget);
      expect(find.text('per night'), findsOneWidget);
      expect(find.text('4.8'), findsOneWidget);
      final AspectRatio ratio = t.widget(find.byType(AspectRatio));
      expect(ratio.aspectRatio, closeTo(3 / 2, 0.001));

      await t.tap(find.text('Choose'));
      await t.pumpAndSettle();
      expect(actions, hasLength(1));
      expect(actions.single.name, 'choose_stay');
      expect(actions.single.sourceComponentId, 'c');
      expect(actions.single.surfaceId, 'test');
      expect(actions.single.context, {'stayId': 'palm-villa', 'nights': 3});
    });

    testWidgets('renders bound props, unit and custom label', (t) async {
      final List<SurfaceAction> actions = [];
      await pumpSurface(
        t,
        single(
          {
            'component': 'StayCard',
            'image': {'path': '/f/image'},
            'name': {'path': '/f/name'},
            'note': {'path': '/f/note'},
            'pricePerNight': {'path': '/f/price'},
            'area': {'path': '/f/area'},
            'priceUnit': 'one way',
            'actionLabel': 'Select',
            'action': event('select_flight', {
              'flightId': {'path': '/f/id'},
            }),
          },
          {
            'f': {
              'id': 'mnl-0605',
              'image': 'siargao-flight',
              'name': 'Manila 06:05',
              'note': 'Direct',
              'price': 4890,
              'area': 'MNL',
            },
          },
        ),
        actions: actions,
      );
      expect(find.text('Manila 06:05'), findsOneWidget);
      expect(find.text('PHP 4,890'), findsOneWidget);
      expect(find.text('one way'), findsOneWidget);
      await t.tap(find.text('Select'));
      await t.pumpAndSettle();
      expect(actions.single.context, {'flightId': 'mnl-0605'});
    });
  });

  group('BudgetSlider', () {
    testWidgets('renders a bound value and writes changes back', (t) async {
      final SurfaceSession session = await pumpSurface(
        t,
        single(
          {
            'component': 'BudgetSlider',
            'label': 'Max price per night',
            'min': 500,
            'max': 10000,
            'step': 500,
            'value': {'path': '/q/max'},
          },
          {
            'q': {'max': 4500},
          },
        ),
      );
      expect(find.text('PHP 4,500'), findsOneWidget);
      expect(find.text('Max price per night'), findsOneWidget);

      final Slider slider = t.widget(find.byType(Slider));
      expect(slider.value, 4500);
      expect(slider.divisions, 19);

      slider.onChanged!(7130);
      await t.pumpAndSettle();
      expect(session.dataAt('/q/max'), 7000);
      expect(find.text('PHP 7,000'), findsOneWidget);
    });

    testWidgets('keeps a literal value locally', (t) async {
      await pumpSurface(
        t,
        single({
          'component': 'BudgetSlider',
          'label': 'Budget',
          'min': 0,
          'max': 1000,
          'step': 100,
          'value': 300,
        }),
      );
      expect(find.text('PHP 300'), findsOneWidget);
      t.widget<Slider>(find.byType(Slider)).onChanged!(810);
      await t.pumpAndSettle();
      expect(find.text('PHP 800'), findsWidgets);
      expect(find.byType(BudgetSliderView), findsOneWidget);
    });
  });

  group('ChipRow', () {
    testWidgets('multi select writes the selection back', (t) async {
      final SurfaceSession session = await pumpSurface(
        t,
        single(
          {
            'component': 'ChipRow',
            'label': 'When can you go?',
            'options': {'path': '/opts'},
            'selected': {'path': '/sel'},
            'multiSelect': true,
          },
          {
            'opts': ['March', 'April', 'May'],
            'sel': ['May'],
          },
        ),
      );
      expect(find.text('When can you go?'), findsOneWidget);
      expect(find.byType(FilterChip), findsNWidgets(3));
      Finder chipFinder(String l) =>
          find.ancestor(of: find.text(l), matching: find.byType(FilterChip));
      FilterChip chip(String l) => t.widget(chipFinder(l));
      expect(chip('May').selected, isTrue);

      await t.tap(chipFinder('March'));
      await t.pumpAndSettle();
      expect(session.dataAt('/sel'), ['March', 'May']);
      expect(chip('March').selected, isTrue);

      await t.tap(chipFinder('May'));
      await t.pumpAndSettle();
      expect(session.dataAt('/sel'), ['March']);
    });

    testWidgets('single select replaces the selection', (t) async {
      final SurfaceSession session = await pumpSurface(
        t,
        single(
          {
            'component': 'ChipRow',
            'options': ['Beginner', 'Intermediate'],
            'selected': {'path': '/level'},
            'multiSelect': false,
          },
          {'level': <String>[]},
        ),
      );
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      await t.tap(find.text('Beginner'));
      await t.pumpAndSettle();
      expect(session.dataAt('/level'), ['Beginner']);
      await t.tap(find.text('Intermediate'));
      await t.pumpAndSettle();
      expect(session.dataAt('/level'), ['Intermediate']);
      expect(find.byType(ChipRowView), findsOneWidget);
    });
  });

  group('LocalNote', () {
    testWidgets('renders each tone with literal props', (t) async {
      await pumpSurface(
        t,
        surfaceMessages('s', [
          {
            'id': 'root',
            'component': 'Stack',
            'children': ['a', 'b', 'c'],
          },
          {
            'id': 'a',
            'component': 'LocalNote',
            'tone': 'tip',
            'title': 'Tip title',
            'body': 'Tip body',
          },
          {
            'id': 'b',
            'component': 'LocalNote',
            'tone': 'heads_up',
            'title': 'Warning title',
            'body': 'Warning body',
          },
          {
            'id': 'c',
            'component': 'LocalNote',
            'tone': 'local',
            'title': 'Local title',
            'body': 'Local body',
            'author': 'From a local',
          },
        ]),
      );
      expect(find.text('TIP'), findsOneWidget);
      expect(find.text('HEADS UP'), findsOneWidget);
      expect(find.text('LOCAL INSIGHT'), findsOneWidget);
      expect(find.text('From a local'), findsOneWidget);
      final List<NoteTone> tones = t
          .widgetList<LocalNoteView>(find.byType(LocalNoteView))
          .map((w) => w.tone)
          .toList();
      expect(tones, [NoteTone.tip, NoteTone.headsUp, NoteTone.local]);
    });

    testWidgets('renders bound props', (t) async {
      await pumpSurface(
        t,
        single(
          {
            'component': 'LocalNote',
            'tone': 'tip',
            'title': {'path': '/n/title'},
            'body': {'path': '/n/body'},
            'author': {'path': '/n/author'},
          },
          {
            'n': {
              'title': 'Bring cash',
              'body': 'ATMs run dry.',
              'author': 'Ana',
            },
          },
        ),
      );
      expect(find.textContaining('Bring'), findsOneWidget);
      expect(find.text('ATMs run dry.'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
    });
  });

  group('FlexGrid', () {
    test('column math balances rows', () {
      expect(SiargaoFlexGrid.columnsFor(1100, 280, 24), 3);
      expect(SiargaoFlexGrid.columnsFor(358, 280, 24), 1);
      expect(SiargaoFlexGrid.balancedColumns(4, 3), 2);
      expect(SiargaoFlexGrid.balancedColumns(5, 3), 3);
      expect(SiargaoFlexGrid.balancedColumns(3, 4), 3);
      expect(SiargaoFlexGrid.balancedColumns(4, 1), 1);
    });

    testWidgets('lays out children in columns at least minItemWidth wide', (
      t,
    ) async {
      await pumpSurface(
        t,
        surfaceMessages('s', [
          {
            'id': 'root',
            'component': 'Stack',
            'children': ['g'],
          },
          {
            'id': 'g',
            'component': 'FlexGrid',
            'children': ['a', 'b', 'c'],
            'minItemWidth': 200,
          },
          {'id': 'a', 'component': 'Heading', 'title': 'Alpha'},
          {'id': 'b', 'component': 'Heading', 'title': 'Bravo'},
          {'id': 'c', 'component': 'Heading', 'title': 'Charlie'},
        ]),
      );
      final double ya = t.getTopLeft(find.text('Alpha')).dy;
      final double yb = t.getTopLeft(find.text('Bravo')).dy;
      final double yc = t.getTopLeft(find.text('Charlie')).dy;
      expect(ya, yb);
      expect(yb, yc);
      expect(find.byType(GridItemScope), findsNWidgets(3));
    });
  });

  group('Actions', () {
    testWidgets('renders styles and dispatches the right action', (t) async {
      final List<SurfaceAction> actions = [];
      await pumpSurface(
        t,
        single(
          {
            'component': 'Actions',
            'buttons': [
              {
                'label': 'Book',
                'style': 'primary',
                'action': event('book_plan', {'days': 4}),
              },
              {
                'label': 'Cheaper',
                'style': 'secondary',
                'action': event('refine_plan', {
                  'change': 'cheaper',
                  'budget': {'path': '/budget'},
                }),
              },
              {
                'label': 'More surf',
                'style': 'text',
                'action': event('refine_plan', {'change': 'more_surf'}),
              },
            ],
          },
          {'budget': 9000},
        ),
        actions: actions,
      );
      expect(find.widgetWithText(FilledButton, 'Book'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cheaper'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'More surf'), findsOneWidget);

      await t.tap(find.text('Cheaper'));
      await t.pumpAndSettle();
      await t.tap(find.text('Book'));
      await t.pumpAndSettle();
      expect(actions.map((a) => a.name), ['refine_plan', 'book_plan']);
      expect(actions.first.context, {'change': 'cheaper', 'budget': 9000});
      expect(actions.last.context, {'days': 4});
      expect(actions.last.toJson().keys, [
        'name',
        'sourceComponentId',
        'surfaceId',
        'context',
        'timestamp',
      ]);
    });

    testWidgets('renders buttons bound to the data model', (t) async {
      await pumpSurface(
        t,
        single(
          {
            'component': 'Actions',
            'buttons': {'path': '/buttons'},
          },
          {
            'buttons': [
              {
                'label': 'Bound button',
                'style': 'primary',
                'action': event('x', {}),
              },
            ],
          },
        ),
      );
      expect(find.widgetWithText(FilledButton, 'Bound button'), findsOneWidget);
    });
  });

  group('images', () {
    test('missing keys and URLs resolve to no asset', () {
      ImageAssets.debugSetAvailable({'assets/img/sugba-lagoon.webp'});
      addTearDown(() => ImageAssets.debugSetAvailable(const {}));
      expect(
        ImageAssets.pathFor('sugba-lagoon'),
        'assets/img/sugba-lagoon.webp',
      );
      expect(ImageAssets.pathFor('guyam-island'), isNull);
      expect(ImageAssets.pathFor('https://example.com/x.jpg'), isNull);
      expect(ImageAssets.altFor('guyam-island'), contains('Guyam'));
    });

    testWidgets('an asset that fails to load falls back to the placeholder', (
      t,
    ) async {
      ImageAssets.debugSetAvailable({'assets/img/naked-island.jpg'});
      addTearDown(() => ImageAssets.debugSetAvailable(const {}));
      await t.pumpWidget(
        themed(
          const SiargaoImage(imageKey: 'naked-island', aspectRatio: 4 / 3),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(ImagePlaceholder), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
