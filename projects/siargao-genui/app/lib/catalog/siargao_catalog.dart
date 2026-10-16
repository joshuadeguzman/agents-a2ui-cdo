import 'package:genui/genui.dart';

import 'actions.dart';
import 'budget_slider.dart';
import 'catalog_schemas.g.dart';
import 'chip_row.dart';
import 'cost_breakdown.dart';
import 'flex_grid.dart';
import 'heading.dart';
import 'itinerary_day.dart';
import 'local_note.dart';
import 'stack.dart';
import 'stay_card.dart';

export 'catalog_schemas.g.dart' show siargaoCatalogId;

/// Every Siargao catalog item, in catalog order.
final List<CatalogItem> siargaoCatalogItems = [
  stackItem,
  headingItem,
  itineraryDayItem,
  costBreakdownItem,
  stayCardItem,
  budgetSliderItem,
  chipRowItem,
  localNoteItem,
  flexGridItem,
  actionsItem,
];

/// The genui [Catalog] for `https://siargao-genui.example/catalogs/v1/catalog.json`.
final Catalog siargaoCatalog = Catalog(
  siargaoCatalogItems,
  catalogId: siargaoCatalogId,
);

/// Component type names the app can render.
final Set<String> siargaoComponentNames = {
  for (final CatalogItem item in siargaoCatalogItems) item.name,
};
