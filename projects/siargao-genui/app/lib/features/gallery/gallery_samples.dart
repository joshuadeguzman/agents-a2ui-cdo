import '../../catalog/catalog_schemas.g.dart';

/// A static sample surface for one catalog component.
class GallerySample {
  /// Creates a [GallerySample].
  const GallerySample({
    required this.component,
    required this.components,
    this.data = const {},
  });

  /// Catalog component name.
  final String component;

  /// Components; the root is always a Stack with id `root`.
  final List<Map<String, Object?>> components;

  /// Data model for bindings.
  final Map<String, Object?> data;

  /// Surface id.
  String get surfaceId => 'gallery_${component.toLowerCase()}';

  /// Catalog description of the component.
  String get description =>
      (siargaoComponentSchemas[component]?['description'] as String?) ?? '';

  /// The three A2UI messages for this sample.
  List<Map<String, Object?>> get messages => [
    {
      'version': 'v0.9',
      'createSurface': {'surfaceId': surfaceId, 'catalogId': siargaoCatalogId},
    },
    {
      'version': 'v0.9',
      'updateComponents': {'surfaceId': surfaceId, 'components': components},
    },
    {
      'version': 'v0.9',
      'updateDataModel': {'surfaceId': surfaceId, 'path': '/', 'value': data},
    },
  ];
}

Map<String, Object?> _root(List<String> children, {String gap = 'medium'}) => {
  'id': 'root',
  'component': 'Stack',
  'children': children,
  'gap': gap,
};

Map<String, Object?> _event(String name, Map<String, Object?> context) => {
  'event': {'name': name, 'context': context},
};

/// One sample per catalog component, in catalog order.
final List<GallerySample> gallerySamples = [
  GallerySample(
    component: 'Stack',
    components: [
      _root(['title', 'note'], gap: 'small'),
      {
        'id': 'title',
        'component': 'Heading',
        'title': 'A Stack places its children top to bottom',
      },
      {
        'id': 'note',
        'component': 'LocalNote',
        'tone': 'tip',
        'title': 'Every surface starts with one',
        'body': 'The root component is always a Stack with the id root.',
      },
    ],
  ),
  GallerySample(
    component: 'Heading',
    components: [
      _root(['hero']),
      {
        'id': 'hero',
        'component': 'Heading',
        'eyebrow': {'path': '/hero/eyebrow'},
        'title': {'path': '/hero/title'},
        'subtitle': {'path': '/hero/subtitle'},
        'image': {'path': '/hero/image'},
      },
    ],
    data: {
      'hero': {
        'eyebrow': '4 days, mid budget',
        'title': 'Your first Siargao trip',
        'subtitle': 'Surf, islands and lagoons, based in General Luna.',
        'image': 'cloud-9-boardwalk',
      },
    },
  ),
  GallerySample(
    component: 'ItineraryDay',
    components: [
      _root(['days']),
      {
        'id': 'days',
        'component': 'FlexGrid',
        'children': ['day-1', 'day-2'],
        'minItemWidth': 300,
      },
      {
        'id': 'day-1',
        'component': 'ItineraryDay',
        'day': {'path': '/days/0/day'},
        'title': {'path': '/days/0/title'},
        'items': {'path': '/days/0/items'},
        'image': {'path': '/days/0/image'},
      },
      {
        'id': 'day-2',
        'component': 'ItineraryDay',
        'day': 2,
        'title': 'Surf lesson and the Maasin river',
        'items': [
          {
            'time': '07:00',
            'activity': 'Beginner surf lesson at Jacking Horse',
            'note': 'About PHP 1,500 with board and coach',
          },
          {'time': '14:30', 'activity': 'Maasin river rope swing'},
        ],
      },
    ],
    data: {
      'days': [
        {
          'day': 1,
          'title': 'Island hopping: Naked, Daku, Guyam',
          'image': 'guyam-island',
          'items': [
            {
              'time': '08:00',
              'activity': 'Boat from the General Luna port',
              'note': 'Shared tour about PHP 1,500 per person',
            },
            {'time': '11:00', 'activity': 'Daku Island, seafood lunch'},
            {'time': '14:00', 'activity': 'Swim at Guyam Island'},
          ],
        },
      ],
    },
  ),
  GallerySample(
    component: 'CostBreakdown',
    components: [
      _root(['budget']),
      {
        'id': 'budget',
        'component': 'CostBreakdown',
        'title': 'Estimated cost per person (sample prices)',
        'currency': 'PHP',
        'items': [
          {'label': 'Return flight from Manila', 'amount': 7500},
          {'label': 'Stay, 3 nights', 'amount': 7500},
          {'label': 'Island hopping tour', 'amount': 1500},
        ],
        'totalLabel': 'Estimated total',
      },
    ],
  ),
  GallerySample(
    component: 'StayCard',
    components: [
      _root(['stays']),
      {
        'id': 'stays',
        'component': 'FlexGrid',
        'children': ['stay-1', 'stay-2'],
        'minItemWidth': 260,
      },
      {
        'id': 'stay-1',
        'component': 'StayCard',
        'image': {'path': '/stay/image'},
        'name': {'path': '/stay/name'},
        'note': {'path': '/stay/note'},
        'pricePerNight': {'path': '/stay/pricePerNight'},
        'area': {'path': '/stay/area'},
        'rating': {'path': '/stay/rating'},
        'action': _event('choose_stay', {
          'stayId': 'cloud9-surf-cabins',
          'nights': 3,
        }),
      },
      {
        'id': 'stay-2',
        'component': 'StayCard',
        'image': 'siargao-flight',
        'name': 'Manila to Siargao, 06:05',
        'note': 'Direct, 1 h 45 min, 7 kg hand carry',
        'pricePerNight': 4890,
        'priceUnit': 'one way',
        'area': 'Manila (MNL)',
        'action': _event('select_flight', {'flightId': 'mnl-iao-0605'}),
        'actionLabel': 'Select',
      },
    ],
    data: {
      'stay': {
        'image': 'stay-cloud9-surf-cabins',
        'name': 'Cloud 9 Surf Cabins',
        'note': 'Thatched cabins with board racks, 3 min walk to the break',
        'pricePerNight': 2800,
        'area': 'Cloud 9',
        'rating': 4.6,
      },
    },
  ),
  GallerySample(
    component: 'BudgetSlider',
    components: [
      _root(['slider']),
      {
        'id': 'slider',
        'component': 'BudgetSlider',
        'label': 'Max price per night',
        'min': 500,
        'max': 10000,
        'step': 500,
        'value': {'path': '/budget/max'},
        'currency': 'PHP',
      },
    ],
    data: {
      'budget': {'max': 4500},
    },
  ),
  GallerySample(
    component: 'ChipRow',
    components: [
      _root(['months', 'length']),
      {
        'id': 'months',
        'component': 'ChipRow',
        'label': 'When can you go?',
        'options': {'path': '/months/options'},
        'selected': {'path': '/prefs/months'},
        'multiSelect': true,
      },
      {
        'id': 'length',
        'component': 'ChipRow',
        'label': 'How long?',
        'options': ['A long weekend', 'One week', 'Two weeks'],
        'selected': {'path': '/prefs/length'},
        'multiSelect': false,
      },
    ],
    data: {
      'months': {
        'options': ['March', 'April', 'May', 'September', 'October'],
      },
      'prefs': {
        'months': ['April', 'September'],
        'length': ['One week'],
      },
    },
  ),
  GallerySample(
    component: 'LocalNote',
    components: [
      _root(['tip', 'heads-up', 'local'], gap: 'small'),
      {
        'id': 'tip',
        'component': 'LocalNote',
        'tone': 'tip',
        'title': 'Bring cash',
        'body': 'ATMs in General Luna often run dry on weekends.',
      },
      {
        'id': 'heads-up',
        'component': 'LocalNote',
        'tone': 'heads_up',
        'title': 'Cloud 9 is a reef break',
        'body': 'Beginners should start at Jacking Horse with a coach.',
      },
      {
        'id': 'local',
        'component': 'LocalNote',
        'tone': 'local',
        'title': 'Go at sunrise',
        'body': 'Walk the boardwalk before the crowds and the heat.',
        'author': 'From a Siargao local',
      },
    ],
  ),
  GallerySample(
    component: 'FlexGrid',
    components: [
      _root(['grid']),
      {
        'id': 'grid',
        'component': 'FlexGrid',
        'children': ['spot-1', 'spot-2', 'spot-3'],
        'minItemWidth': 220,
      },
      {
        'id': 'spot-1',
        'component': 'Heading',
        'eyebrow': 'Del Carmen',
        'title': 'Sugba Lagoon',
        'subtitle': 'Paddle board on clear turquoise water.',
        'image': 'sugba-lagoon',
      },
      {
        'id': 'spot-2',
        'component': 'Heading',
        'eyebrow': 'Pilar',
        'title': 'Magpupungko rock pools',
        'subtitle': 'Go at low tide.',
        'image': 'magpupungko-pools',
      },
      {
        'id': 'spot-3',
        'component': 'Heading',
        'eyebrow': 'San Isidro',
        'title': 'Pacifico beach',
        'subtitle': 'Quiet waves on the north east coast.',
        'image': 'pacifico-beach',
      },
    ],
  ),
  GallerySample(
    component: 'Actions',
    components: [
      _root(['actions']),
      {
        'id': 'actions',
        'component': 'Actions',
        'buttons': [
          {
            'label': 'Book this plan',
            'style': 'primary',
            'action': _event('book_plan', {'days': 4}),
          },
          {
            'label': 'Make it cheaper',
            'style': 'secondary',
            'action': _event('refine_plan', {'change': 'cheaper'}),
          },
          {
            'label': 'Add a surf day',
            'style': 'text',
            'action': _event('refine_plan', {'change': 'more_surf'}),
          },
        ],
      },
    ],
  ),
];
